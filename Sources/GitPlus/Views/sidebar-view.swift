import SwiftUI

/// Native (Liquid Glass) sidebar: groups as expandable rows, repositories inside.
/// Drag repos between groups, double-click a group to rename it, right-click for actions.
struct SidebarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: SidebarSelection?

    @State private var filter = ""
    @State private var renamingKey: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @AppStorage("collapsedGroups") private var collapsedRaw = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(store.groups) { group in
                groupSection(key: .group(group.id), name: group.name, groupID: group.id)
            }
            if !store.repos(in: nil).isEmpty || store.groups.isEmpty {
                groupSection(key: .ungrouped, name: "Ungrouped", groupID: nil)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filter, placement: .sidebar, prompt: "Filter repositories")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
    }

    // MARK: Rows

    private func groupSection(key: SidebarSelection, name: String, groupID: UUID?) -> some View {
        let repos = store.repos(in: groupID).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        return DisclosureGroup(isExpanded: expanded(key.rawValue)) {
            ForEach(repos) { repo in
                SidebarRepoRow(repo: repo, status: store.statuses[repo.id], isBusy: store.busy.contains(repo.id))
                    .tag(SidebarSelection.repo(repo.id))
                    .draggable(repo.id.uuidString)
                    .contextMenu { RepoContextMenu(repo: repo, selection: $selection) }
            }
        } label: {
            groupLabel(key: key, name: name, groupID: groupID, count: repos.count)
                .tag(key)
        }
    }

    private func groupLabel(key: SidebarSelection, name: String, groupID: UUID?, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: groupID == nil ? "tray" : "folder.fill")
                .foregroundStyle(groupID == nil ? Color.secondary : Color.accentColor)
            if renamingKey == key.rawValue {
                TextField("Group name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commitRename(key: key) }
                    .onExitCommand { renamingKey = nil }
            } else {
                Text(name).fontWeight(.semibold)
            }
            Spacer()
            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(key: key.rawValue, current: name) })
        .dropDestination(for: String.self) { items, _ in
            store.move(repoIDs: items.compactMap(UUID.init(uuidString:)), to: groupID)
            return true
        }
        .contextMenu {
            let ids = store.repos(in: groupID).map(\.id)
            Button("Fetch All") { Task { await store.fetch(ids) } }
            Button("Pull All (fast-forward)") { Task { await store.pull(ids) } }
            Divider()
            Button("Rename…") { startRename(key: key.rawValue, current: name) }
            if let groupID {
                Button("Delete Group (keep repositories)", role: .destructive) {
                    if selection == key { selection = nil }
                    store.deleteGroup(groupID)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Menu {
                Button("Add Repositories…") { addRepositories() }
                Button("New Group") {
                    let group = store.createGroup(named: "New Group")
                    startRename(key: SidebarSelection.group(group.id).rawValue, current: group.name)
                }
                Divider()
                Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            Spacer()
            Button { Task { await store.refreshStatus() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.glass)
                .help("Refresh status of all repositories (⌘R)")
        }
        .padding(10)
    }

    // MARK: State helpers

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    private func expanded(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) || !filter.isEmpty },
            set: { open in
                var set = collapsed
                if open { set.remove(key) } else { set.insert(key) }
                collapsedRaw = set.sorted().joined(separator: ",")
            }
        )
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
        let groupID: UUID? = switch selection {
        case .group(let id): id
        case .repo(let id): store.repo(id)?.groupID
        default: nil
        }
        let urls = FolderPicker.choose()
        Task { await store.add(folders: urls, to: groupID) }
    }
}

struct SidebarRepoRow: View {
    let repo: RepoEntry
    let status: RepoStatus?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProviderIcon(provider: status?.remote?.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).lineLimit(1)
                if let status {
                    Label(status.branch, systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isBusy { ProgressView().controlSize(.mini) } else if let status { SyncBadge(status: status) }
        }
        .padding(.vertical, 2)
    }
}
