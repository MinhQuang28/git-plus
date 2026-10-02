import SwiftUI

/// "Current Repository" dropdown: repos grouped by workspace groups, with filter,
/// drag & drop between groups and inline rename (double-click a group header).
struct RepositoryPickerView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: SidebarSelection?
    @Binding var isPresented: Bool

    @State private var filter = ""
    /// `group:<uuid>` or `ungrouped` while a header is being renamed.
    @State private var renamingKey: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
                Menu {
                    Button("Add Repositories…") { addRepositories() }
                    Button("New Group") { startRename(key: SidebarSelection.group(store.createGroup(named: "New Group").id).rawValue, current: "New Group") }
                    Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
                } label: { Text("Add") }
                .fixedSize()
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.groups) { group in
                        section(key: SidebarSelection.group(group.id), name: group.name, groupID: group.id)
                    }
                    if !store.repos(in: nil).isEmpty {
                        section(key: .ungrouped, name: "Ungrouped", groupID: nil)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 380, height: 500)
    }

    // MARK: Sections

    @ViewBuilder
    private func section(key: SidebarSelection, name: String, groupID: UUID?) -> some View {
        let repos = store.repos(in: groupID).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        if filter.isEmpty || !repos.isEmpty {
            header(key: key, name: name, groupID: groupID, count: repos.count)
            ForEach(repos) { repoRow($0) }
        }
    }

    private func header(key: SidebarSelection, name: String, groupID: UUID?, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: groupID == nil ? "tray" : "folder")
            if renamingKey == key.rawValue {
                TextField("Group name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFocused)
                    .onSubmit { commitRename(key: key) }
                    .onExitCommand { renamingKey = nil }
            } else {
                Text(name).font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selection == key ? Color.accentColor.opacity(0.25) : Theme.headerBackground)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename(key: key.rawValue, current: name) }
        .onTapGesture { select(key) }
        .dropDestination(for: String.self) { items, _ in
            store.move(repoIDs: items.compactMap(UUID.init(uuidString:)), to: groupID)
            return true
        }
        .contextMenu {
            let ids = store.repos(in: groupID).map(\.id)
            Button("Open Group Overview") { select(key) }
            Button("Fetch All") { Task { await store.fetch(ids) } }
            Button("Pull All (fast-forward)") { Task { await store.pull(ids) } }
            Divider()
            Button("Rename…") { startRename(key: key.rawValue, current: name) }
            if let groupID {
                Button("Delete Group (keep repos)", role: .destructive) {
                    if selection == key { selection = nil }
                    store.deleteGroup(groupID)
                }
            }
        }
    }

    private func repoRow(_ repo: RepoEntry) -> some View {
        let status = store.statuses[repo.id]
        let isSelected = selection == .repo(repo.id)
        return HStack(spacing: 8) {
            ProviderIcon(provider: status?.remote?.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).lineLimit(1)
                if let status { Text(status.branch).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if store.busy.contains(repo.id) { ProgressView().controlSize(.small) } else if let status { SyncBadge(status: status) }
        }
        .padding(.leading, 26).padding(.trailing, 10).padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.35) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { select(.repo(repo.id)) }
        .draggable(repo.id.uuidString)
        .contextMenu { RepoContextMenu(repo: repo, selection: $selection) }
    }

    // MARK: Actions

    private func select(_ key: SidebarSelection) {
        selection = key
        isPresented = false
    }

    private func startRename(key: String, current: String) {
        renameText = current
        renamingKey = key
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(key: SidebarSelection) {
        defer { renamingKey = nil }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch key {
        case .group(let id): store.renameGroup(id, to: name)
        case .ungrouped:
            if let id = store.renameUngrouped(to: name), selection == .ungrouped { selection = .group(id) }
        case .repo: break
        }
    }

    private func addRepositories() {
        let groupID: UUID? = if case .group(let id) = selection { id } else { nil }
        isPresented = false
        let urls = FolderPicker.choose()
        Task { await store.add(folders: urls, to: groupID) }
    }
}

struct RepoContextMenu: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    @Binding var selection: SidebarSelection?

    var body: some View {
        Button("Fetch") { Task { await store.fetch([repo.id]) } }
        Button("Pull (fast-forward)") { Task { await store.pull([repo.id]) } }
        Divider()
        Menu("Move to Group") {
            ForEach(store.groups) { g in Button(g.name) { store.move(repoIDs: [repo.id], to: g.id) } }
            Divider()
            Button("Ungrouped") { store.move(repoIDs: [repo.id], to: nil) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
        Button("Open in Terminal") {
            NSWorkspace.shared.open([repo.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())
        }
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
