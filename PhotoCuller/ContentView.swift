import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ReviewViewModel()

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            switch vm.phase {
            case .launching, .loadingLibrary:
                LoadingView(library: PhotoLibraryManager.shared)

            case .requestingPermission:
                PermissionView(vm: vm)

            case .reviewing:
                ReviewView(vm: vm)

            case .confirmingDeletion(let toDelete, let kept):
                ConfirmDeletionView(vm: vm, toDelete: toDelete, keepCount: kept)

            case .batchComplete(let deleted, let kept):
                BatchCompleteView(vm: vm, deleted: deleted, kept: kept)

            case .libraryExhausted:
                LibraryExhaustedView(vm: vm)

            case .error(let message):
                ErrorView(message: message, vm: vm)
            }
        }
        .onAppear {
            NSApp.mainWindow?.makeFirstResponder(nil)
        }
    }
}
