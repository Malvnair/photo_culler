import SwiftUI
import Photos
import Combine

// MARK: - Review Decision

enum ReviewDecision {
    case keep
    case delete
}

// MARK: - Review Item

struct ReviewItem: Identifiable {
    let id: String
    var decision: ReviewDecision?
    var image: NSImage?
    var asset: PHAsset?
    var isLoading: Bool = true
    var loadFailed: Bool = false


    var pixelDimensions: String? {
        guard let a = asset else { return nil }
        return "\(a.pixelWidth) × \(a.pixelHeight)"
    }

    var dateString: String? {
        guard let date = asset?.creationDate else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - App Phase

enum AppPhase {
    case launching
    case requestingPermission
    case loadingLibrary
    case reviewing
    case confirmingDeletion(toDelete: [ReviewItem], toKeep: Int)
    case batchComplete(deleted: Int, kept: Int)
    case libraryExhausted
    case error(String)
}

// MARK: - ReviewViewModel

@MainActor
class ReviewViewModel: ObservableObject {

    @Published var phase: AppPhase = .launching
    @Published var items: [ReviewItem] = []
    @Published var currentIndex: Int = 0
    @Published var isDeletionInProgress: Bool = false

    private let library = PhotoLibraryManager.shared
    private var currentBatch: PhotoBatch?
    private var cancellables = Set<AnyCancellable>()


    private var batchKeepCount = 0
    private var batchDeleteCount = 0

    // MARK: - Init

    init() {

        library.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleAuthState(state)
            }
            .store(in: &cancellables)

        library.$shuffledIDsLoaded
            .receive(on: RunLoop.main)
            .sink { [weak self] loaded in
                if loaded { self?.loadNextBatch() }
            }
            .store(in: &cancellables)

        library.checkExistingAuthorization()
    }

    // MARK: - Auth Handling

    private func handleAuthState(_ state: AuthorizationState) {
        switch state {
        case .notDetermined:
            phase = .requestingPermission
        case .restricted:
            phase = .error("Photo library access is restricted on this device.")
        case .denied:
            phase = .error("Photo library access was denied. Please enable it in System Settings > Privacy & Security > Photos.")
        case .authorized, .limited:
            if case .requestingPermission = phase {
                phase = .loadingLibrary
            }
        }
    }

    func requestPermission() async {
        phase = .loadingLibrary
        await library.requestAuthorization()
    }

    // MARK: - Batch Management

    private func loadNextBatch() {
        guard let batch = library.nextBatch() else {
            phase = .libraryExhausted
            return
        }
        currentBatch = batch
        batchKeepCount = 0
        batchDeleteCount = 0


        items = batch.assetIDs.map { ReviewItem(id: $0) }
        currentIndex = 0
        phase = .reviewing


        let preCacheIDs = Array(batch.assetIDs.prefix(8))
        library.preCache(assetIDs: preCacheIDs)


        loadImage(at: 0)
    }

    // MARK: - Image Loading

    func loadImage(at index: Int) {
        guard index < items.count else { return }
        guard items[index].image == nil && !items[index].loadFailed else { return }

        let id = items[index].id
        library.loadImage(for: id) { [weak self] image, asset in
            guard let self = self else { return }
            guard index < self.items.count, self.items[index].id == id else { return }

            if let image = image {
                self.items[index].image = image
                self.items[index].asset = asset
                self.items[index].isLoading = false
            } else if !self.items[index].isLoading {

            } else {

                self.items[index].isLoading = false
                self.items[index].loadFailed = true
            }
        }
    }

    private func preloadUpcoming(from index: Int) {
        let range = (index + 1)..<min(index + 6, items.count)
        for i in range {
            if items[i].image == nil {
                loadImage(at: i)
            }
        }
    }

    // MARK: - Keyboard Actions

    func handleKey(_ key: String) {
        switch phase {
        case .reviewing:
            switch key {
            case "1": keepCurrent()
            case "0": markCurrentForDeletion()
            default: break
            }
        case .confirmingDeletion(let toDelete, let kept):
            switch key {
            case "0": confirmDeletion(toDelete: toDelete, kept: kept)
            case "1": cancelDeletion()
            default: break
            }
        default:
            break
        }
    }

    // MARK: - Review Actions

    private func keepCurrent() {
        guard currentIndex < items.count else { return }
        items[currentIndex].decision = .keep
        batchKeepCount += 1
        advance()
    }

    private func markCurrentForDeletion() {
        guard currentIndex < items.count else { return }
        items[currentIndex].decision = .delete
        batchDeleteCount += 1
        advance()
    }

    private func advance() {
        let next = currentIndex + 1
        if next >= items.count {

            finishBatch()
        } else {
            currentIndex = next
            preloadUpcoming(from: next)
        }
    }

    private func finishBatch() {
        let toDelete = items.filter { $0.decision == .delete }
        let keepCount = items.filter { $0.decision == .keep }.count

        if toDelete.isEmpty {

            phase = .batchComplete(deleted: 0, kept: keepCount)
        } else {
            phase = .confirmingDeletion(toDelete: toDelete, toKeep: keepCount)
        }
    }

    // MARK: - Deletion Confirmation

    func confirmDeletion(toDelete: [ReviewItem], kept: Int) {
        isDeletionInProgress = true
        let idsToDelete = toDelete.map { $0.id }

        Task {
            let (count, errorMsg) = await library.deleteAssets(withIDs: idsToDelete)
            isDeletionInProgress = false

            if let err = errorMsg {

                phase = .error("Deletion failed: \(err)\n\nRestart the app to continue reviewing.")
            } else {
                phase = .batchComplete(deleted: count, kept: kept)
            }


            if let batch = currentBatch {
                library.stopCaching(assetIDs: batch.assetIDs)
            }
        }
    }

    func cancelDeletion() {

        let keepCount = items.filter { $0.decision == .keep }.count
        let deleteCount = items.filter { $0.decision == .delete }.count
        phase = .batchComplete(deleted: 0, kept: keepCount + deleteCount)
    }

    func proceedToNextBatch() {
        loadNextBatch()
    }

    func resetAndReshuffle() async {
        phase = .loadingLibrary
        await library.resetProgress()

    }

    // MARK: - Current Item Accessor

    var currentItem: ReviewItem? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var batchProgress: String {
        "\(min(currentIndex + 1, items.count)) / \(items.count)"
    }

    var globalProgress: String {
        let reviewed = (currentBatch?.batchIndex ?? 0) * PhotoLibraryManager.batchSize + currentIndex
        return "\(reviewed.formatted()) / \(library.totalAssetCount.formatted()) total"
    }
}
