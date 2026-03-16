import Photos
import AppKit
import Combine

// MARK: - Models

enum AuthorizationState {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
}

struct PhotoBatch {
    let batchIndex: Int
    let assetIDs: [String]
    var currentIndex: Int = 0

    var currentAssetID: String? {
        guard currentIndex < assetIDs.count else { return nil }
        return assetIDs[currentIndex]
    }

    var isExhausted: Bool {
        currentIndex >= assetIDs.count
    }

    var progress: String {
        "\(min(currentIndex + 1, assetIDs.count)) / \(assetIDs.count)"
    }
}

// MARK: - PhotoLibraryManager

@MainActor
class PhotoLibraryManager: ObservableObject {

    static let shared = PhotoLibraryManager()

    // MARK: Published state
    @Published var authState: AuthorizationState = .notDetermined
    @Published var isLoading: Bool = false
    @Published var totalAssetCount: Int = 0
    @Published var shuffledIDsLoaded: Bool = false

    // MARK: Constants
    static let batchSize = 30
    static let persistenceKey = "shuffledAssetIDs_v2"
    static let progressKey = "globalAssetIndex_v2"

    // MARK: Private storage
    private var shuffledIDs: [String] = []
    private(set) var globalIndex: Int = 0

    private let imageManager = PHCachingImageManager()

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authState = mapStatus(status)
        if authState == .authorized || authState == .limited {
            await loadLibrary()
        }
    }

    func checkExistingAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authState = mapStatus(status)
        if authState == .authorized || authState == .limited {
            Task { await loadLibrary() }
        }
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .limited:       return .limited
        @unknown default:    return .denied
        }
    }

    // MARK: - Library Loading

    private func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }


        if let saved = UserDefaults.standard.array(forKey: Self.persistenceKey) as? [String],
           !saved.isEmpty {

            let sampleFetch = PHAsset.fetchAssets(withLocalIdentifiers: Array(saved.prefix(10)), options: nil)
            if sampleFetch.count > 0 {
                shuffledIDs = saved
                globalIndex = UserDefaults.standard.integer(forKey: Self.progressKey)
                totalAssetCount = shuffledIDs.count
                shuffledIDsLoaded = true
                return
            }
        }


        await buildShuffledIndex()
    }

    private func buildShuffledIndex() async {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = []


        let result = PHAsset.fetchAssets(with: .image, options: options)

        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }


        var rng = SystemRandomNumberGenerator()
        for i in stride(from: ids.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i, using: &rng)
            ids.swapAt(i, j)
        }

        shuffledIDs = ids
        globalIndex = 0
        totalAssetCount = ids.count


        UserDefaults.standard.set(ids, forKey: Self.persistenceKey)
        UserDefaults.standard.set(0, forKey: Self.progressKey)

        shuffledIDsLoaded = true
    }

    // MARK: - Batch Serving


    func nextBatch() -> PhotoBatch? {
        guard globalIndex < shuffledIDs.count else { return nil }

        let batchNumber = globalIndex / Self.batchSize
        let end = min(globalIndex + Self.batchSize, shuffledIDs.count)
        let batchIDs = Array(shuffledIDs[globalIndex..<end])

        globalIndex = end
        UserDefaults.standard.set(globalIndex, forKey: Self.progressKey)

        return PhotoBatch(batchIndex: batchNumber, assetIDs: batchIDs)
    }


    var remainingCount: Int {
        max(0, shuffledIDs.count - globalIndex)
    }


    func resetProgress() async {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        UserDefaults.standard.removeObject(forKey: Self.progressKey)
        shuffledIDsLoaded = false
        isLoading = true
        await buildShuffledIndex()
        isLoading = false
    }

    // MARK: - Image Loading

    private let reviewSize = CGSize(width: 1400, height: 1400)

    func loadImage(
        for assetID: String,
        size: CGSize? = nil,
        fullResolution: Bool = false,
        completion: @escaping (NSImage?, PHAsset?) -> Void
    ) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetchResult.firstObject else {
            completion(nil, nil)
            return
        }

        let targetSize: CGSize
        let deliveryMode: PHImageRequestOptionsDeliveryMode
        let resizeMode: PHImageRequestOptionsResizeMode

        if fullResolution {
            targetSize = PHImageManagerMaximumSize
            deliveryMode = .highQualityFormat
            resizeMode = .none
        } else {
            targetSize = size ?? reviewSize
            deliveryMode = .opportunistic
            resizeMode = .fast
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = resizeMode
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        options.progressHandler = { progress, error, _, _ in

            if let error = error {
                print("[PhotoCuller] iCloud download error: \(error)")
            }
        }

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false


            DispatchQueue.main.async {
                completion(image, asset)
            }
        }
    }


    func preCache(assetIDs: [String]) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { a, _, _ in assets.append(a) }

        imageManager.startCachingImages(
            for: assets,
            targetSize: reviewSize,
            contentMode: .aspectFit,
            options: nil
        )
    }

    func stopCaching(assetIDs: [String]) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { a, _, _ in assets.append(a) }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: reviewSize,
            contentMode: .aspectFit,
            options: nil
        )
    }

    // MARK: - Deletion


    func deleteAssets(withIDs ids: [String]) async -> (Int, String?) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { a, _, _ in assets.append(a) }

        guard !assets.isEmpty else {
            return (0, "No matching assets found in library.")
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume(returning: (assets.count, nil))
                } else {
                    let msg = error?.localizedDescription ?? "Unknown error"
                    continuation.resume(returning: (0, msg))
                }
            })
        }
    }
}
