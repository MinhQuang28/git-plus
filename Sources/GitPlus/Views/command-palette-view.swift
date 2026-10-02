import AppKit
import SwiftUI

/// ⌘K: fuzzy-search repositories, groups, branches of the open repository and every command.
struct CommandPaletteView: View {
    @Environment(WorkspaceStore.self) private var store
    let dismiss: () -> Void

    struct Item: Identifiable {
        let id: String
        let title: String
        var subtitle: String = ""
        let symbol: String
        var shortcut: String? = nil
        let run: @MainActor () -> Void
    }

    @State private var query = ""
    @State private var highlighted = 0
    @State private var branches = BranchList()
    @FocusState private var focused: Bool

    private var repoID: UUID? { RepoActions.currentRepoID }

    private var results: [Item] {
        let all = commands + repositories + branchItems
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return Array(all.prefix(40)) }
        return all.compactMap { item in FuzzyMatch.score(query, item.title).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .map { $0.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Search commands, repositories, branches…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { activate(highlighted) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
            }
            .padding(Spacing.l)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let items = results
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isHighlighted: index == highlighted)
                                .id(index)
                                .onTapGesture { activate(index) }
                        }
                        if items.isEmpty {
                            Text("No matches").foregroundStyle(.secondary).padding(Spacing.xl)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 600)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onExitCommand(perform: dismiss)
        .task {
            if let id = repoID, let repo = store.repo(id) { branches = (try? await GitService(repo: repo.url).branches()) ?? BranchList() }
        }
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: item.symbol).frame(width: 20).foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let shortcut = item.shortcut { KeyboardHint(keys: shortcut) }
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .background(isHighlighted ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: Radius.s))
        .padding(.horizontal, Spacing.xs)
        .contentShape(Rectangle())
    }

    private func activate(_ index: Int) {
        let items = results
        guard items.indices.contains(index) else { return }
        dismiss()
        items[index].run()
    }

    // MARK: Items

    private var repositories: [Item] {
        let groups = store.groups.map { group in
            Item(id: "group:\(group.id)", title: group.name, subtitle: "Group · \(store.repos(in: group.id).count) repositories",
                 symbol: "folder") { RepoActions.select(.group(group.id)) }
        }
        let repos = store.workspace.repos.map { repo in
            Item(id: "repo:\(repo.id)", title: repo.name,
                 subtitle: [store.statuses[repo.id]?.branch, repo.path].compactMap { $0 }.joined(separator: " · "),
                 symbol: "book.closed") { RepoActions.select(.repo(repo.id)) }
        }
        return repos + groups
    }

    private var branchItems: [Item] {
        guard let id = repoID else { return [] }
        return branches.local.filter { $0 != branches.current }.map { name in
            Item(id: "branch:\(name)", title: name, subtitle: "Switch to branch", symbol: "arrow.triangle.branch") {
                Task { await store.perform(id, "switch branch", success: "Switched to \(name)") { try await $0.switchBranch(name) } }
            }
        }
    }

    private var commands: [Item] {
        var items: [Item] = [
            Item(id: "cmd:add", title: "Add Repositories…", symbol: "plus.rectangle.on.folder", shortcut: "⌘O") { RepoActions.addRepositories(store) },
            Item(id: "cmd:clone", title: "Clone Repository…", symbol: "square.and.arrow.down", shortcut: "⇧⌘O") { RepoActions.post(.showClone) },
            Item(id: "cmd:new", title: "New Repository…", symbol: "plus.square", shortcut: "⌘N") { RepoActions.newRepository(store) },
            Item(id: "cmd:refresh", title: "Refresh All Status", symbol: "arrow.clockwise", shortcut: "⌘R") { Task { await store.refreshStatus() } },
            Item(id: "cmd:activity", title: "Show Activity", symbol: "list.bullet.rectangle") { RepoActions.post(.showActivity) },
            Item(id: "cmd:autogroup", title: "Auto-Group by Remote", symbol: "folder.badge.gearshape") { Task { await store.autoGroupByRemote() } },
        ]
        guard let id = repoID, let repo = store.repo(id) else { return items }
        items += [
            Item(id: "cmd:changes", title: "Show Changes", symbol: "pencil", shortcut: "⌘1") { RepoActions.show(.changes) },
            Item(id: "cmd:history", title: "Show History", symbol: "clock", shortcut: "⌘2") { RepoActions.show(.history) },
            Item(id: "cmd:stashes", title: "Show Stashes", symbol: "tray", shortcut: "⌘3") { RepoActions.show(.stashes) },
            Item(id: "cmd:fetch", title: "Fetch", symbol: "arrow.triangle.2.circlepath", shortcut: "⇧⌘F") { Task { await store.fetch([id]) } },
            Item(id: "cmd:pull", title: "Pull", symbol: "arrow.down.circle", shortcut: "⇧⌘L") { Task { await store.pull([id]) } },
            Item(id: "cmd:pullrebase", title: "Pull with Rebase", symbol: "arrow.down.circle") { Task { await store.pull([id], mode: .rebase) } },
            Item(id: "cmd:pullmerge", title: "Pull with Merge", symbol: "arrow.down.circle") { Task { await store.pull([id], mode: .merge) } },
            Item(id: "cmd:push", title: "Push", symbol: "arrow.up.circle", shortcut: "⇧⌘P") { Task { await store.push(id) } },
            Item(id: "cmd:forcepush", title: "Force Push (with Lease)…", symbol: "exclamationmark.arrow.circlepath", shortcut: "⌥⇧⌘P") {
                ForcePushConfirmation.run(store, id)
            },
            Item(id: "cmd:merge", title: "Merge into Current Branch…", symbol: "arrow.triangle.merge", shortcut: "⇧⌘M") { RepoActions.post(.showMerge) },
            Item(id: "cmd:conflicts", title: "Resolve Conflicts…", symbol: "wand.and.stars") { RepoActions.post(.showConflicts) },
            Item(id: "cmd:undo", title: "Undo Last Commit", symbol: "arrow.uturn.backward") { RepoActions.undoLastCommit(store, id) },
            Item(id: "cmd:branches", title: "Show Branch List", symbol: "arrow.triangle.branch", shortcut: "⌘B") { RepoActions.post(.showBranchPicker) },
            Item(id: "cmd:remotes", title: "Remotes…", symbol: "network") { RepoActions.post(.showRemotes) },
            Item(id: "cmd:editor", title: "Open in Editor", symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⇧⌘E") {
                RepoActions.open(repo, editor: true)
            },
            Item(id: "cmd:terminal", title: "Open in Terminal", symbol: "terminal", shortcut: "⌃`") { RepoActions.open(repo, editor: false) },
            Item(id: "cmd:finder", title: "Reveal in Finder", symbol: "folder", shortcut: "⇧⌘R") { RepoActions.reveal(repo) },
            Item(id: "cmd:pin", title: repo.isPinned == true ? "Unpin Repository" : "Pin Repository", symbol: "pin") { store.togglePin(id) },
        ]
        if let web = store.statuses[id]?.remote?.webURL {
            items.append(Item(id: "cmd:web", title: "Open on Web", symbol: "safari") { NSWorkspace.shared.open(web) })
        }
        return items
    }
}
