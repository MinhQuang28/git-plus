import SwiftUI

/// Window root: repository or group workspace. The repository list drops down from the
/// "Current Repository" header of the left column (no permanent sidebar).
struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("selection") private var storedSelection = ""
    @State private var switcher = SwitcherState()

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { SidebarSelection(rawValue: storedSelection) }, set: { storedSelection = $0?.rawValue ?? "" })
    }

    var body: some View {
        @Bindable var store = store
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(switcher)
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
            if let group = store.group(id) { GroupWorkspaceView(groupID: id, selection: selection, title: group.name).id(id) } else { placeholder }
        case .ungrouped:
            GroupWorkspaceView(groupID: nil, selection: selection, title: "Ungrouped").id("ungrouped")
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                SwitcherColumn(forceExpanded: true) { EmptyView() }
            }
            welcome.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label(store.workspace.repos.isEmpty ? "No Repositories" : "No Selection", systemImage: "square.stack.3d.up")
        } description: {
            Text("Add repositories with ⌘O, then pick one from the list on the left.")
        } actions: {
            Button("Add Repositories…") {
                let urls = FolderPicker.choose()
                Task { await store.add(folders: urls, to: nil) }
            }
        }
    }
}
