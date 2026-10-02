import SwiftUI

/// "Add" menu for a group: add local folders (scanned for repos) or move repositories
/// that already live in another group into this one.
struct AddToGroupMenu<Label: View>: View {
    @Environment(WorkspaceStore.self) private var store
    let groupID: UUID?
    @ViewBuilder var label: () -> Label

    private var others: [RepoEntry] {
        store.workspace.repos.filter { $0.groupID != groupID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            Button("Add Local Repository…") {
                let urls = FolderPicker.choose()
                guard !urls.isEmpty else { return }
                Task { await store.add(folders: urls, to: groupID) }
            }
            Menu("Move Existing Repository Here") {
                if others.isEmpty { Text("Every repository is already in this group") }
                ForEach(others) { repo in
                    Button("\(repo.name)  —  \(groupName(repo.groupID))") { store.move(repoIDs: [repo.id], to: groupID) }
                }
            }
            .disabled(others.isEmpty)
        } label: {
            label()
        }
    }

    private func groupName(_ id: UUID?) -> String {
        id.flatMap { store.group($0)?.name } ?? "Ungrouped"
    }
}
