import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: SidebarSelection?
    @State private var newGroupName = ""
    @State private var isCreatingGroup = false
    @State private var renaming: RepoGroup?

    var body: some View {
        List(selection: $selection) {
            ForEach(store.groups) { group in
                DisclosureGroup {
                    ForEach(store.repos(in: group.id)) { repoRow($0) }
                } label: {
                    groupLabel(group.name, count: store.repos(in: group.id).count, groupID: group.id)
                        .tag(SidebarSelection.group(group.id))
                        .contextMenu { groupMenu(group) }
                }
            }
            let ungrouped = store.repos(in: nil)
            if !ungrouped.isEmpty || store.groups.isEmpty {
                DisclosureGroup {
                    ForEach(ungrouped) { repoRow($0) }
                } label: {
                    groupLabel("Ungrouped", count: ungrouped.count, groupID: nil)
                        .tag(SidebarSelection.ungrouped)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button { isCreatingGroup = true } label: { Label("New Group", systemImage: "folder.badge.plus") }
                Button {
                    let urls = FolderPicker.choose()
                    Task { await store.add(folders: urls, to: currentGroupID) }
                } label: { Label("Add Repositories", systemImage: "plus") }
            }
        }
        .alert("New Group", isPresented: $isCreatingGroup) {
            TextField("Name", text: $newGroupName)
            Button("Create") { selection = .group(store.createGroup(named: newGroupName).id); newGroupName = "" }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .alert("Rename Group", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newGroupName)
            Button("Rename") { if let g = renaming { store.renameGroup(g.id, to: newGroupName) }; newGroupName = "" }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
    }

    /// Group that new repos are added to, based on the current selection.
    private var currentGroupID: UUID? {
        switch selection {
        case .group(let id): id
        case .repo(let id): store.repo(id)?.groupID
        default: nil
        }
    }

    private func groupLabel(_ name: String, count: Int, groupID: UUID?) -> some View {
        HStack {
            Label(name, systemImage: groupID == nil ? "tray" : "folder")
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
        .dropDestination(for: String.self) { items, _ in
            store.move(repoIDs: items.compactMap(UUID.init(uuidString:)), to: groupID)
            return true
        }
    }

    private func repoRow(_ repo: RepoEntry) -> some View {
        RepoRowView(repo: repo, status: store.statuses[repo.id], isBusy: store.busy.contains(repo.id))
            .tag(SidebarSelection.repo(repo.id))
            .draggable(repo.id.uuidString)
            .contextMenu { repoMenu(repo) }
    }

    @ViewBuilder private func groupMenu(_ group: RepoGroup) -> some View {
        let ids = store.repos(in: group.id).map(\.id)
        Button("Fetch All") { Task { await store.fetch(ids) } }
        Button("Pull All (fast-forward)") { Task { await store.pull(ids) } }
        Divider()
        Button("Rename…") { newGroupName = group.name; renaming = group }
        Button("Delete Group (keep repos)", role: .destructive) { store.deleteGroup(group.id) }
    }

    @ViewBuilder private func repoMenu(_ repo: RepoEntry) -> some View {
        Button("Fetch") { Task { await store.fetch([repo.id]) } }
        Button("Pull (fast-forward)") { Task { await store.pull([repo.id]) } }
        Divider()
        Menu("Move to Group") {
            ForEach(store.groups) { g in Button(g.name) { store.move(repoIDs: [repo.id], to: g.id) } }
            Divider()
            Button("Ungrouped") { store.move(repoIDs: [repo.id], to: nil) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
        Button("Open in Terminal") { NSWorkspace.shared.open([repo.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init()) }
        if let web = store.statuses[repo.id]?.remote?.webURL {
            Button("Open on Web") { NSWorkspace.shared.open(web) }
        }
        Divider()
        Button("Remove from Git Plus", role: .destructive) {
            if selection == .repo(repo.id) { selection = nil }
            store.remove(repoIDs: [repo.id])
        }
    }
}
