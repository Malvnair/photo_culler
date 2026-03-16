import SwiftUI
import Photos

// MARK: - LoadingView

struct LoadingView: View {
    @ObservedObject var library: PhotoLibraryManager

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Text(library.isLoading ? "Scanning photo library…" : "Starting up…")
                .font(.headline)

            if library.totalAssetCount > 0 {
                Text("\(library.totalAssetCount.formatted()) photos found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("This happens once. Your progress is saved automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PermissionView

struct PermissionView: View {
    @ObservedObject var vm: ReviewViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Photo Culler")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This app needs access to your Photos library to help you review and clean up photos.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "eye", text: "View photos from your library")
                InfoRow(icon: "trash", text: "Move unwanted photos to Recently Deleted")
                InfoRow(icon: "lock.shield", text: "Your data never leaves your device")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Button("Grant Access to Photos") {
                Task { await vm.requestPermission() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - BatchCompleteView

struct BatchCompleteView: View {
    @ObservedObject var vm: ReviewViewModel
    let deleted: Int
    let kept: Int

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Batch Complete")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 40) {
                StatBlock(value: kept, label: "Kept", color: .green)
                StatBlock(value: deleted, label: "Deleted", color: .red)
            }

            let remaining = PhotoLibraryManager.shared.remainingCount
            if remaining > 0 {
                Text("\(remaining.formatted()) photos remaining in queue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Start Next Batch →") {
                    vm.proceedToNextBatch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Text("You've reviewed all photos in the queue!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Reshuffle & Start Over") {
                    Task { await vm.resetAndReshuffle() }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatBlock: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - LibraryExhaustedView

struct LibraryExhaustedView: View {
    @ObservedObject var vm: ReviewViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundColor(.yellow)

            Text("All Done!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("You've reviewed your entire photo library.")
                .font(.body)
                .foregroundColor(.secondary)

            Button("Reshuffle & Start Over") {
                Task { await vm.resetAndReshuffle() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ErrorView

struct ErrorView: View {
    let message: String
    @ObservedObject var vm: ReviewViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    Task { await vm.requestPermission() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FullScreenView

struct FullScreenView: View {
    let assetID: String
    @State private var image: NSImage? = nil
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if let img = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: CGFloat(img.size.width),
                            maxHeight: CGFloat(img.size.height)
                        )
                }
            } else {
                Text("Could not load full resolution image.")
                    .foregroundColor(.secondary)
            }


            VStack {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .padding()
                }
                Spacer()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadFullRes()
        }
        .onExitCommand { dismiss() }
    }

    private func loadFullRes() {
        PhotoLibraryManager.shared.loadImage(for: assetID, fullResolution: true) { img, _ in
            image = img
            isLoading = false
        }
    }
}
