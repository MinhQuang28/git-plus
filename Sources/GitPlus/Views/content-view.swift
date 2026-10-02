import SwiftUI

struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var selection: SidebarSelection?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            detail
        }
        .task { await store.refreshStatus() }
        .alert("Git Plus", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .repo(let id):
            if let repo = store.repo(id) {
                RepoDetailView(repo: repo).id(repo.id)
            } else {
                placeholder
            }
        case .group(let id):
            if let group = store.group(id) {
                GroupOverviewView(groupID: group.id, title: group.name).id(group.id)
            } else {
                placeholder
            }
        case .ungrouped:
            GroupOverviewView(groupID: nil, title: "Ungrouped").id("ungrouped")
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label("No Selection", systemImage: "square.stack.3d.up")
        } description: {
            Text("Add repositories with ⌘O, then select a group or repository.")
        } actions: {
            Button("Add Repositories…") {
                let urls = FolderPicker.choose()
                Task { await store.add(folders: urls, to: nil) }
            }
        }
    }
}
