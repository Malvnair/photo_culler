import SwiftUI

struct ConfirmDeletionView: View {
    @ObservedObject var vm: ReviewViewModel
    let toDelete: [ReviewItem]
    let keepCount: Int

    private let thumbSize: CGFloat = 100
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.red)

                Text("Confirm Deletion")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(toDelete.count) photo\(toDelete.count == 1 ? "" : "s") will be moved to the Recently Deleted album.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("\(keepCount) kept this batch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)

            Divider()
                .padding(.vertical, 16)


            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(toDelete) { item in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: thumbSize, height: thumbSize)

                            if let img = item.image {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: thumbSize, height: thumbSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }


                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.red, lineWidth: 2)
                                .frame(width: thumbSize, height: thumbSize)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 350)

            Divider()
                .padding(.vertical, 16)


            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    Button(action: { vm.cancelDeletion() }) {
                        HStack {
                            KeyBadge(key: "1")
                            Text("Skip Deletion, Keep All")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button(action: {
                        vm.confirmDeletion(toDelete: toDelete, kept: keepCount)
                    }) {
                        HStack {
                            KeyBadge(key: "0")
                            Text("Confirm Delete \(toDelete.count) Photo\(toDelete.count == 1 ? "" : "s")")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }

                if vm.isDeletionInProgress {
                    ProgressView("Moving to Recently Deleted…")
                        .progressViewStyle(.linear)
                }

                Text("Press 0 to confirm deletion · Press 1 to skip and keep all")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(KeyEventHandler { key in
            switch key {
            case "0": vm.confirmDeletion(toDelete: toDelete, kept: keepCount)
            case "1": vm.cancelDeletion()
            default: break
            }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
