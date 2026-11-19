import AppKit
import SwiftUI

/// Always-visible repository list in the left column: filter + Add, one section per group, Ungrouped. Click a group title to fold it, its chevron opens the group overview, drag repos onto it (rename from the context menu).
struct RepositoryListPanel: View {
    @Environment(WorkspaceStore.self) private var store
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
        withAnimation(Motion.safe(.easeInOut(duration: 0.15))) { collapsedRaw = set.sorted().joined(separator: ",") }
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
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $filter).textFieldStyle(.plain).focused($filterFocused)
                    .onSubmit(openHighlighted)
                    .onKeyPress(.downArrow) { moveHighlight(1) }
                    .onKeyPress(.upArrow) { moveHighlight(-1) }
            }
            .filterFieldStyle()
            .padding(8)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let pinned = store.pinnedRepos.filter(matches)
                    if !pinned.isEmpty {
                        HStack(spacing: 4) {
                            Text("Pinned").textCase(.uppercase).appFont(.callout).foregroundStyle(.secondary)
                            Image(systemName: "pin.fill").appFont(size: 9).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Menu {
                    Button("Add Repositories…") { addRepositories() }
                    Button("New Group") {
                        let group = store.createGroup(named: "New Group")
                        startRename(SidebarSelection.group(group.id).rawValue, group.name)
                    }
                    Divider()
                    Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .tint(.primary)   // neutral; the accent marks the current repository only
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            // Opaque like the panel, so rows scrolling underneath don't show through the footer.
            .background(Theme.paneBackground.overlay(Theme.panelBackground))
        }
        .onReceive(NotificationCenter.default.publisher(for: .showRepositoryPicker)) { _ in filterFocused = true }
        .onChange(of: filter) { highlightedID = filter.isEmpty ? nil : visibleRepos.first?.id }
        .onExitCommand { filter = ""; filterFocused = false }
    }

    @ViewBuilder private func section(_ key: SidebarSelection, name: String, groupID: UUID?) -> some View {
        let repos = store.repos(in: groupID).filter(matches)
        if !repos.isEmpty || (groupID != nil && filter.isEmpty) {
            Divider().padding(.horizontal, Spacing.s).padding(.top, Spacing.s)
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
                // Quiet section label (name + fold chevron), so the repositories carry the weight.
                Text(name).textCase(.uppercase).appFont(.callout).foregroundStyle(.secondary).lineLimit(1).help(name)
                Button { toggleCollapsed(key) } label: {
                    Label(isCollapsed(key) ? "Show repositories" : "Hide repositories", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                        .appFont(size: 10, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed(key) ? -90 : 0))
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed(key) ? "Show repositories" : "Hide repositories")
                Spacer()
                Button { pick(key) } label: {
                    Label("Open \(name) Overview", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .imageScale(.small)
                        .appFont(.caption, weight: .medium)
                }
                .buttonStyle(.borderless)
                .tint(.secondary)   // a borderless button draws its label in the tint
                .help("Open the \(name) overview")
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { if renamingKey != key.rawValue { toggleCollapsed(key) } }
        .hoverHighlight()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) group, \(count) repositories")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleCollapsed(key) }
        .accessibilityAction(named: "Open Group Overview") { pick(key) }
        .dropDestination(for: String.self) { items, _ in
            store.move(repoIDs: items.compactMap(UUID.init(uuidString:)), to: groupID)
            return true
        }
        .contextMenu {
            let ids = store.repos(in: groupID).map(\.id)
            Button("Open Group Overview") { pick(key) }
            Button("Fetch All") { Task { await store.fetch(ids) } }
            Button("Pull All") { Task { await store.pull(ids) } }
            Divider()
            Button("Rename…") { startRename(key.rawValue, name) }
            if let groupID {
                Button("Delete Group…", role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = "Delete “\(name)”?"
                    alert.informativeText = "Its \(count == 1 ? "repository moves" : "\(count) repositories move") to Ungrouped. Nothing on disk changes."
                    alert.addButton(withTitle: "Delete Group")
                    alert.addButton(withTitle: "Cancel")
                    alert.buttons.first?.hasDestructiveAction = true
                    Task {
                        guard await WindowAlert.run(alert) == .alertFirstButtonReturn else { return }
                        if selection == key { storedSelection = "" }
                        store.deleteGroup(groupID)
                    }
                }
            }
        }
    }

    /// `pinned`: the copy in the Pinned section (gets its own scroll id; the group copy is the scroll target).
    private func row(_ repo: RepoEntry, pinned: Bool = false) -> some View {
        let status = store.statuses[repo.id]
        let isCurrent = selection == .repo(repo.id)
        let isHighlighted = highlightedID == repo.id
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        return HStack(spacing: 10) {
            RepoInitialTile(name: repo.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).appFont(size: 14).lineLimit(1)
                Text(status?.branch ?? " ").appFont(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if store.busy.contains(repo.id) {
                ProgressView().controlSize(.mini)
            } else if let status {
                SyncBadge(status: status)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(isCurrent ? Theme.accent.opacity(0.22) : isHighlighted ? Theme.accent.opacity(0.12) : .clear, in: shape)
        .overlay { if isHighlighted { shape.stroke(Theme.accent, lineWidth: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { pick(.repo(repo.id)) }
        .hoverHighlight()
        .clipShape(shape)
        .padding(.horizontal, Spacing.xs)
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

/// Rounded letter tile identifying a repository: a stable muted hue per name, its first letter in white.
struct RepoInitialTile: View {
    let name: String
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)   // the name is read from the row
    }

    private var color: Color {
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.3, brightness: 0.55)
    }
}
