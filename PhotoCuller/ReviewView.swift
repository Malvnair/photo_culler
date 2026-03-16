import SwiftUI
import AppKit

// MARK: - ReviewView

struct ReviewView: View {
    @ObservedObject var vm: ReviewViewModel
    @State private var showingFullScreen = false
    @State private var overlayLabel: String? = nil
    @State private var overlayColor: Color = .green

    var body: some View {
        VStack(spacing: 0) {

            topBar

            Divider()


            ZStack {
                Color.black

                if let item = vm.currentItem {
                    if item.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else if item.loadFailed {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Failed to load image")
                                .foregroundColor(.secondary)
                            Text("Press 0 or 1 to continue")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if let img = item.image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onTapGesture(count: 2) {
                                showingFullScreen = true
                            }
                    }
                }


                if let label = overlayLabel {
                    Text(label)
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(overlayColor)
                        .shadow(radius: 4)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()


            bottomBar
        }
        .background(KeyEventHandler { key in
            handleKey(key)
        })
        .sheet(isPresented: $showingFullScreen) {
            if let item = vm.currentItem {
                FullScreenView(assetID: item.id)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Batch Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(vm.batchProgress)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            Spacer()

            VStack(alignment: .center, spacing: 2) {
                Text("Photo Culler")
                    .font(.headline)
                if let item = vm.currentItem, let date = item.dateString {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Library Progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(vm.globalProgress)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {

            if let item = vm.currentItem, let dims = item.pixelDimensions {
                Label(dims, systemImage: "camera")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()


            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    KeyBadge(key: "0")
                    Text("Delete")
                        .foregroundColor(.red)
                }
                HStack(spacing: 6) {
                    KeyBadge(key: "1")
                    Text("Keep")
                        .foregroundColor(.green)
                }
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.caption)
                    Text("Double-click: Full View")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()


            Text("\(PhotoLibraryManager.shared.remainingCount.formatted()) remaining")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Key Handler

    private func handleKey(_ key: String) {
        vm.handleKey(key)


        switch key {
        case "0":
            flashOverlay("✕", color: .red)
        case "1":
            flashOverlay("✓", color: .green)
        default:
            break
        }
    }

    private func flashOverlay(_ text: String, color: Color) {
        overlayLabel = text
        overlayColor = color
        withAnimation(.easeIn(duration: 0.05)) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) {
                overlayLabel = nil
            }
        }
    }
}

// MARK: - Key Badge

struct KeyBadge: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            )
    }
}

// MARK: - KeyEventHandler (NSViewRepresentable)

struct KeyEventHandler: NSViewRepresentable {
    let onKey: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onKey = onKey
        return v
    }
    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKey = onKey
    }
}

class KeyCaptureView: NSView {
    var onKey: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { return }
        onKey?(chars)
    }
}
