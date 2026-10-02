import SwiftUI

/// Drop-down repository list (GitHub Desktop style): filter + Add, one section per group, Ungrouped. Click a group title to open its overview, double-click to rename, drag repos onto it.
struct RepositoryListPanel: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SwitcherState.self) private var switcher
    @AppStorage("selection") private var storedSelection = ""

    @State private var filter = ""
    @State private var renamingKey: String?
    @State private var renameText = ""
    @FocusState private var filterFocused: Bool
    @FocusState private var renameFocused: Bool

    private var selection: SidebarSelection? { SidebarSelection(rawValue: storedSelection) }
    private func matches(_ repo: RepoEntry) -> Bool { filter.isEmpty || repo.name.localizedCaseInsensitiveContains(filter) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter", text: $filter).textFieldStyle(.plain).focused($filterFocused)
                        .onSubmit(openFirstMatch)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                Menu {
                    Button("Add Repositories…") { addRepositories() }
                    Button("New Group") {
                        let group = store.createGroup(named: "New Group")
                        startRename(SidebarSelection.group(group.id).rawValue, group.name)
                    }
                    Divider()
                    Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
                } label: { Text("Add") }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()
            }
            .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let pinned = store.pinnedRepos.filter(matches)
                    if !pinned.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                            Text("Pinned").font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                        ForEach(pinned) { row($0) }
                    }
                    ForEach(store.groups) { group in
                        section(.group(group.id), name: group.name, groupID: group.id)
                    }
                    section(.ungrouped, name: "Ungrouped", groupID: nil)
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear { filterFocused = true }
        .onExitCommand { switcher.isExpanded = false }
    }

    @ViewBuilder private func section(_ key: SidebarSelection, name: String, groupID: UUID?) -> some View {
        let repos = store.repos(in: groupID).filter(matches)
        if !repos.isEmpty || (groupID != nil && filter.isEmpty) {
            groupTitle(key, name: name, groupID: groupID, count: repos.count)
            ForEach(repos) { row($0) }
        }
    }

    private func groupTitle(_ key: SidebarSelection, name: String, groupID: UUID?, count: Int) -> some View {
        HStack(spacing: 6) {
            if renamingKey == key.rawValue {
                TextField("Group name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFocused)
                    .onSubmit { commitRename(key) }
                    .onExitCommand { renamingKey = nil }
            } else {
                // Folder icon sets groups apart from the repository rows below them.
                Image(systemName: groupID == nil ? "tray.fill" : "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(groupID == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 18)
                Text(name).font(.system(size: 13, weight: .bold))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "rectangle.grid.1x2").font(.caption).foregroundStyle(.secondary)
                    .help("Open group overview")
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename(key.rawValue, name) }
        .onTapGesture { pick(key) }
        .hoverHighlight()
        .dropDestination(for: String.self) { items, _ in
            store.move(repoIDs: items.compactMap(UUID.init(uuidString:)), to: groupID)
            return true
        }
        .contextMenu {
            let ids = store.repos(in: groupID).map(\.id)
            Button("Open Group Overview") { pick(key) }
            Button("Fetch All") { Task { await store.fetch(ids) } }
            Button("Pull All (fast-forward)") { Task { await store.pull(ids) } }
            Divider()
            Button("Rename…") { startRename(key.rawValue, name) }
            if let groupID {
                Button("Delete Group (keep repositories)", role: .destructive) {
                    if selection == key { storedSelection = "" }
                    store.deleteGroup(groupID)
                }
            }
        }
    }

    private func row(_ repo: RepoEntry) -> some View {
        let status = store.statuses[repo.id]
        let isCurrent = selection == .repo(repo.id)
        return HStack(spacing: 10) {
            ProviderIcon(provider: status?.remote?.provider)
            Text(repo.name).lineLimit(1)
            Spacer(minLength: 4)
            if store.busy.contains(repo.id) {
                ProgressView().controlSize(.mini)
            } else if let status {
                SyncBadge(status: status)
            }
        }
        .padding(.horizontal, 14).frame(height: 32)
        .background(isCurrent ? Color.accentColor.opacity(0.22) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { pick(.repo(repo.id)) }
        .hoverHighlight()
        .draggable(repo.id.uuidString)
        .contextMenu { RepoContextMenu(repo: repo, selection: selectionBinding) }
        .help(repo.path)
    }

    // MARK: Actions

    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(get: { selection }, set: { storedSelection = $0?.rawValue ?? "" })
    }

    private func pick(_ key: SidebarSelection) {
        storedSelection = key.rawValue
        switcher.isExpanded = false
    }

    private func openFirstMatch() {
        if let first = (store.groups.map(\.id).map(Optional.some) + [nil]).flatMap({ store.repos(in: $0) }).first(where: matches) {
            pick(.repo(first.id))
        }
    }

    private func startRename(_ key: String, _ current: String) {
        renameText = current
        renamingKey = key
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename(_ key: SidebarSelection) {
        defer { renamingKey = nil }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch key {
        case .group(let id): store.renameGroup(id, to: name)
        case .ungrouped:
            if let id = store.renameUngrouped(to: name), selection == .ungrouped { storedSelection = SidebarSelection.group(id).rawValue }
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
