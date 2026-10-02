import SwiftUI

/// Window root: GitHub Desktop–style top bar + repository or group workspace.
struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("selection") private var storedSelection = ""

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { SidebarSelection(rawValue: storedSelection) }, set: { storedSelection = $0?.rawValue ?? "" })
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            TopBarView(selection: selection)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.paneBackground)
        .overlay(alignment: .bottom) {
            if let toast = store.toast { ToastView(toast: toast).id(toast.id) }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .task { await store.refreshStatus() }
        .alert("Git Plus", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch selection.wrappedValue {
        case .repo(let id):
            if let repo = store.repo(id) { RepoWorkspaceView(repo: repo).id(repo.id) } else { placeholder }
        case .group(let id):
            if store.group(id) != nil { GroupWorkspaceView(groupID: id, selection: selection).id(id) } else { placeholder }
        case .ungrouped:
            GroupWorkspaceView(groupID: nil, selection: selection).id("ungrouped")
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(store.workspace.repos.isEmpty ? "No Repositories" : "No Selection", systemImage: "square.stack.3d.up")
        } description: {
            Text("Add repositories with ⌘O, or pick one from “Current Repository” above.")
        } actions: {
            Button("Add Repositories…") {
                let urls = FolderPicker.choose()
                Task { await store.add(folders: urls, to: nil) }
            }
        }
    }
}
