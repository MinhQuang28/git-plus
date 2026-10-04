import SwiftUI

/// Drop-down repository list (GitHub Desktop style): filter + Add, one section per group, Ungrouped. Click a group title to open its overview, double-click to rename, drag repos onto it.
struct RepositoryListPanel: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SwitcherState.self) private var switcher
    @AppStorage("selection") private var storedSelection = ""
    /// Comma-separated `SidebarSelection.rawValue`s of collapsed groups (persisted).
    @AppStorage("collapsedGroups") private var collapsedRaw = ""

    @State private var filter = ""
    @State private var renamingKey: String?
    @State private var renameText = ""
    @FocusState private var filterFocused: Bool
    @FocusState private var renameFocused: Bool
    /// Keyboard highlight (↑/↓ in the filter field, Return opens it).
    @State private var highlightedID: UUID?

    private var selection: SidebarSelection? { SidebarSelection(rawValue: storedSelection) }
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    /// A filter always shows every match, even inside collapsed groups.
    private func isCollapsed(_ key: SidebarSelection) -> Bool { filter.isEmpty && collapsed.contains(key.rawValue) }

    private func toggleCollapsed(_ key: SidebarSelection) {
        var set = collapsed
        if set.remove(key.rawValue) == nil { set.insert(key.rawValue) }
        withAnimation(.easeInOut(duration: 0.15)) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    private func matches(_ repo: RepoEntry) -> Bool { filter.isEmpty || repo.name.localizedCaseInsensitiveContains(filter) }

    /// Repositories in on-screen order (pinned first, collapsed groups skipped), each once.
    private var visibleRepos: [RepoEntry] {
        var seen = Set<UUID>()
        let sections = store.groups.map { (SidebarSelection.group($0.id), Optional($0.id)) } + [(.ungrouped, nil)]
        let grouped = sections.flatMap { key, id in isCollapsed(key) ? [] : store.repos(in: id).filter(matches) }
        return (store.pinnedRepos.filter(matches) + grouped).filter { seen.insert($0.id).inserted }
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        let repos = visibleRepos
        guard !repos.isEmpty else { return .ignored }
        let current = repos.firstIndex { $0.id == highlightedID } ?? (delta > 0 ? -1 : repos.count)
        highlightedID = repos[min(max(current + delta, 0), repos.count - 1)].id
        return .handled
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter", text: $filter).textFieldStyle(.plain).focused($filterFocused)
                        .onSubmit(openHighlighted)
                        .onKeyPress(.downArrow) { moveHighlight(1) }
                        .onKeyPress(.upArrow) { moveHighlight(-1) }
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
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let pinned = store.pinnedRepos.filter(matches)
                    if !pinned.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill").appFont(.caption).foregroundStyle(.secondary)
                            Text("Pinned").appFont(size: 13, weight: .bold)
                        }
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                        ForEach(pinned) { row($0, pinned: true) }
                    }
                    ForEach(store.groups) { group in
                        section(.group(group.id), name: group.name, groupID: group.id)
                    }
                    section(.ungrouped, name: "Ungrouped", groupID: nil)
                }
                .padding(.bottom, 10)
            }
            .onChange(of: highlightedID) { _, id in if let id { proxy.scrollTo(id.uuidString) } }
            }
        }
        .onAppear { filterFocused = true }
        .onChange(of: filter) { highlightedID = filter.isEmpty ? nil : visibleRepos.first?.id }
        .onExitCommand { switcher.isExpanded = false }
    }

    @ViewBuilder private func section(_ key: SidebarSelection, name: String, groupID: UUID?) -> some View {
        let repos = store.repos(in: groupID).filter(matches)
        if !repos.isEmpty || (groupID != nil && filter.isEmpty) {
            groupTitle(key, name: name, groupID: groupID, count: repos.count)
            if !isCollapsed(key) { ForEach(repos) { row($0) } }
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
                Button { toggleCollapsed(key) } label: {
                    Image(systemName: "chevron.right")
                        .appFont(size: 10, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed(key) ? 0 : 90))
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed(key) ? "Show repositories" : "Hide repositories")
                // Folder icon sets groups apart from the repository rows below them.
                Image(systemName: groupID == nil ? "tray.fill" : "folder.fill")
                    .appFont(size: 13)
                    .foregroundStyle(groupID == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 18)
                Text(name).appFont(size: 13, weight: .bold)
                Text("\(count)").appFont(.caption, monospacedDigit: true).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "rectangle.grid.1x2").appFont(.caption).foregroundStyle(.secondary)
                    .help("Open group overview")
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename(key.rawValue, name) }
        .onTapGesture { pick(key) }
        .hoverHighlight()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) group, \(count) repositories")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pick(key) }
        .accessibilityAction(named: isCollapsed(key) ? "Expand" : "Collapse") { toggleCollapsed(key) }
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

    /// `pinned`: the copy in the Pinned section (gets its own scroll id; the group copy is the scroll target).
    private func row(_ repo: RepoEntry, pinned: Bool = false) -> some View {
        let status = store.statuses[repo.id]
        let isCurrent = selection == .repo(repo.id)
        let isHighlighted = highlightedID == repo.id
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
        .padding(.horizontal, 14).frame(minHeight: 32)
        .background(isCurrent ? Color.accentColor.opacity(0.22) : isHighlighted ? Color.accentColor.opacity(0.12) : .clear)
        .overlay { if isHighlighted { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1).padding(.horizontal, 4) } }
        .contentShape(Rectangle())
        .onTapGesture { pick(.repo(repo.id)) }
        .hoverHighlight()
        .id(pinned ? "pinned:\(repo.id)" : repo.id.uuidString)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { pick(.repo(repo.id)) }
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

    /// Return in the filter: the highlighted repository, else the first match.
    private func openHighlighted() {
        if let id = highlightedID ?? visibleRepos.first?.id { pick(.repo(id)) }
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
