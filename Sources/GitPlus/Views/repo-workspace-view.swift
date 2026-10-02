import AppKit
import SwiftUI

/// Detail area for one repository: list column (Changes / History / Stashes) + diff.
struct RepoWorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry

    @AppStorage("repoTab") private var tab = RepoTab.history
    @AppStorage("autoFetch") private var autoFetch = true

    @State private var selectedCommits: [Commit] = []
    @State private var tree = WorkingTree()
    @State private var selectedChange: ChangedFile.ID?
    @State private var stashes: [StashEntry] = []
    @State private var selectedStash: StashEntry.ID?
    @State private var activationTick = 0

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }
    private var status: RepoStatus? { store.statuses[repo.id] }

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                SwitcherColumn {
                    Group {
                        switch tab {
                        case .changes: ChangesPaneView(repo: repo, tree: tree, selection: $selectedChange)
                        case .history: HistoryPaneView(repo: repo, remote: status?.remote, selected: $selectedCommits)
                        case .stashes: StashListView(stashes: stashes, selection: $selectedStash)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let op = status?.operation {
                OperationBannerView(repo: repo, operation: op, conflicts: status?.conflicts ?? 0)
            }
        }
        .navigationTitle(repo.name)          // window menu / Mission Control only
        .toolbar(removing: .title)            // the name is already in "Current Repository"
        .toolbar {
            RepoToolbar(repo: repo, status: status, tab: $tab, changeCount: tree.count, stashCount: stashes.count)
        }
        .task(id: "\(revision)|\(activationTick)") { await reload() }
        .task(id: autoFetch) {
            // Auto-fetch while this repository is open.
            while autoFetch && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, autoFetch else { break }
                await store.backgroundFetch(repo.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            activationTick += 1
            Task { await store.refreshStatus([repo.id]) }
        }
    }

    @ViewBuilder private var main: some View {
        switch tab {
        case .changes:
            if let file = tree.all.first(where: { $0.id == selectedChange }) {
                FileDiffView(source: .workingTree(git), file: file, repoID: repo.id, reloadKey: revision &+ activationTick)
                    .id(file.id)
            } else {
                ContentUnavailableView(tree.isEmpty ? "No Local Changes" : "Select a File",
                                       systemImage: tree.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass",
                                       description: Text(tree.isEmpty ? "Your working directory is clean." : "Choose a file to see its changes."))
            }
        case .history:
            if let target = DiffTarget.range(selectedCommits) {
                CommitDetailView(repoURL: repo.url, target: target,
                                 commit: selectedCommits.count == 1 ? selectedCommits.first : nil, remote: status?.remote)
            } else {
                ContentUnavailableView("Select a Commit", systemImage: "clock.arrow.circlepath",
                                       description: Text("⌘-click or ⇧-click several commits to see their combined diff."))
            }
        case .stashes:
            if let entry = stashes.first(where: { $0.id == selectedStash }) {
                StashDetailView(repo: repo, entry: entry).id(entry.id)
            } else {
                ContentUnavailableView("No Stash Selected", systemImage: "tray")
            }
        }
    }

    private func reload() async {
        async let loadedTree = git.workingTree()
        async let loadedStashes = git.stashes()
        tree = (try? await loadedTree) ?? WorkingTree()
        stashes = (try? await loadedStashes) ?? []
        if !tree.all.contains(where: { $0.id == selectedChange }) { selectedChange = tree.all.first?.id }
        if !stashes.contains(where: { $0.id == selectedStash }) { selectedStash = stashes.first?.id }
    }
}
