import AppKit
import SwiftUI

/// Request to show a file's history or blame (sheet owned by `RepoWorkspaceView`).
struct FileInspection: Identifiable, Hashable {
    enum Mode: Hashable { case history, blame }
    var id: String { "\(mode)|\(path)" }
    let path: String
    var mode: Mode
}

/// Opens file history / blame. Equatable by repository so passing it down doesn't invalidate
/// readers on every parent render (closures never compare equal).
struct InspectFileAction: Equatable {
    let repoID: UUID
    let handler: (FileInspection) -> Void
    func callAsFunction(_ item: FileInspection) { handler(item) }
    static func == (a: Self, b: Self) -> Bool { a.repoID == b.repoID }
}

struct InspectFileKey: EnvironmentKey { static let defaultValue: InspectFileAction? = nil }

extension EnvironmentValues {
    /// Opens file history / blame for a path in the current repository.
    var inspectFile: InspectFileAction? {
        get { self[InspectFileKey.self] }
        set { self[InspectFileKey.self] = newValue }
    }
}

/// Detail area for one repository: status header + list column (Changes / History / Stashes) + diff.
struct RepoWorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry

    @AppStorage("repoTab") private var tab = RepoTab.changes
    @AppStorage("autoFetch") private var autoFetch = true

    @State private var selectedCommits: [Commit] = []
    @State private var selectedChanges = Set<ChangedFile.ID>()
    @State private var stashes: [StashEntry] = []
    @State private var selectedStash: StashEntry.ID?
    @State private var activationTick = 0
    @State private var watcher: FileWatcher?
    @State private var pendingExternalChange: Task<Void, Never>?
    /// Paths reported by FSEvents since the last debounced refresh.
    @State private var pendingPaths = Set<String>()
    @State private var inspection: FileInspection?
    @State private var showConflicts = false
    @State private var showMerge = false
    @State private var showRemotes = false

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }
    /// Working-tree-only changes (files edited outside Git Plus): reload changes, not history.
    private var worktreeRevision: Int { store.worktreeRevisions[repo.id] ?? 0 }
    private var status: RepoStatus? { store.statuses[repo.id] }
    /// Filled by the store's status refresh (one `git status` for the toolbar and the Changes tab).
    private var tree: WorkingTree { store.trees[repo.id] ?? WorkingTree() }

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                SwitcherColumn {
                    VStack(spacing: 0) {
                        RepoStatusHeader(repo: repo, status: status)
                        Group {
                            switch tab {
                            case .changes: ChangesPaneView(repo: repo, tree: tree, selection: $selectedChanges)
                            case .history: HistoryPaneView(repo: repo, remote: status?.remote, selected: $selectedCommits)
                            case .stashes: StashListView(stashes: stashes, selection: $selectedStash)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let op = status?.operation {
                OperationBannerView(repo: repo, operation: op, conflicts: status?.conflicts ?? 0) { showConflicts = true }
            }
        }
        .environment(\.inspectFile, InspectFileAction(repoID: repo.id) { inspection = $0 })
        .navigationTitle(repo.name)          // window menu / Mission Control only
        .toolbar(removing: .title)            // the name is already in "Current Repository"
        .toolbar {
            RepoToolbar(repo: repo, status: status, tab: $tab, changeCount: tree.count, stashCount: stashes.count)
        }
        .task(id: "\(revision)|\(activationTick)") { await reloadStashes() }
        .onChange(of: tree) { _, tree in fixSelection(tree) }
        .task(id: autoFetch) {
            // Auto-fetch while this repository is open.
            while autoFetch && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, autoFetch else { break }
                await store.backgroundFetch(repo.id)
            }
        }
        .onAppear {
            store.setOpen(repo.id, true)
            fixSelection(tree)
            Task { await store.refreshStatus([repo.id]) }
            startWatching()
        }
        .onDisappear {
            store.setOpen(repo.id, false)
            watcher = nil
            pendingExternalChange?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            activationTick += 1
            Task { await store.refreshStatus([repo.id]) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showConflicts)) { _ in showConflicts = true }
        .onReceive(NotificationCenter.default.publisher(for: .showMerge)) { _ in showMerge = true }
        .onReceive(NotificationCenter.default.publisher(for: .showRemotes)) { _ in showRemotes = true }
        .onChange(of: status?.conflicts ?? 0) { old, new in
            // Like GitHub Desktop: conflicts appearing after a merge / rebase open the resolve dialog.
            if old == 0, new > 0, status?.operation != nil { showConflicts = true }
        }
        .sheet(isPresented: $showConflicts) { ConflictsSheet(repo: repo) { showConflicts = false } }
        .sheet(isPresented: $showMerge) { MergeSheet(repo: repo) { showMerge = false } }
        .sheet(isPresented: $showRemotes) { RemotesSheet(repo: repo) { showRemotes = false } }
        .branchSwitchDialog(repoID: repo.id)
        .sheet(item: $inspection) { item in
            FileInspectorView(repo: repo, path: item.path, mode: item.mode, remote: status?.remote) { inspection = nil }
        }
    }

    private var selectedFiles: [ChangedFile] { tree.all.filter { selectedChanges.contains($0.id) } }

    @ViewBuilder private var main: some View {
        switch tab {
        case .changes:
            let files = selectedFiles
            if files.count == 1, let file = files.first {
                if file.area == .conflicted {
                    ConflictFileView(repo: repo, file: file).id(file.id)
                } else {
                    FileDiffView(source: .workingTree(git), file: file, repoID: repo.id, reloadKey: revision &+ worktreeRevision &+ activationTick)
                        .id(file.id)
                }
            } else if files.count > 1 {
                MultiSelectionView(repo: repo, files: files) { selectedChanges = [] }
            } else {
                ContentUnavailableView(tree.isEmpty ? "No Local Changes" : "Select a File",
                                       systemImage: tree.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass",
                                       description: Text(tree.isEmpty ? "Your working directory is clean." : "Choose a file to see its changes. ⌘-click to select several."))
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

    /// Reload when files change outside Git Plus. Events are collected for 400 ms; changes that only
    /// touch `.gitignore`d files are dropped, and history reloads only when refs / HEAD changed.
    private func startWatching() {
        let id = repo.id, git = self.git
        watcher = FileWatcher(folder: repo.url) { paths in
            pendingPaths.formUnion(paths)
            pendingExternalChange?.cancel()
            pendingExternalChange = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let batch = pendingPaths
                pendingPaths = []
                let affectsHistory = batch.contains(where: FileWatcher.affectsHistory)
                let gitInternal = batch.filter(FileWatcher.isGitInternal)
                let worktree = batch.subtracting(gitInternal)
                if gitInternal.isEmpty, !worktree.isEmpty, worktree.count <= 200 {
                    let ignored = await git.ignoredPaths(Array(worktree))
                    if ignored.count == worktree.count { return }   // only ignored files (build output, caches)
                }
                await store.noteExternalChange(id, affectsHistory: affectsHistory)
            }
        }
    }

    private func reloadStashes() async {
        guard let loaded = try? await git.stashes() else { return }
        stashes = loaded
        if !stashes.contains(where: { $0.id == selectedStash }) { selectedStash = stashes.first?.id }
    }

    /// Keeps the Changes selection valid after the file list changes (defaults to the first file).
    private func fixSelection(_ tree: WorkingTree) {
        let all = tree.all
        let ids = Set(all.map(\.id))
        let kept = selectedChanges.intersection(ids)
        let next = kept.isEmpty ? Set(all.first.map { [$0.id] } ?? []) : kept
        if next != selectedChanges { selectedChanges = next }
    }
}

/// Main area while several changed files are selected: bulk actions.
struct MultiSelectionView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let files: [ChangedFile]
    let clear: () -> Void
    @State private var confirmDiscard = false

    private var unstaged: [ChangedFile] { files.filter { $0.area == .unstaged } }
    private var staged: [ChangedFile] { files.filter { $0.area == .staged } }

    var body: some View {
        ContentUnavailableView {
            Label("\(files.count) Files Selected", systemImage: "doc.on.doc")
        } description: {
            Text(summary)
        } actions: {
            HStack(spacing: Spacing.s) {
                if !unstaged.isEmpty {
                    Button("Stage \(unstaged.count)") { run("stage") { [unstaged] in try await $0.stage(unstaged) } }
                        .buttonStyle(.glassProminent)
                }
                if !staged.isEmpty {
                    Button("Unstage \(staged.count)") { run("unstage") { [staged] in try await $0.unstage(staged) } }
                        .buttonStyle(.glass)
                }
                Button("Stash \(files.count)…") {
                    let paths = Array(Set(files.flatMap(\.pathspec)))
                    run("stash", success: "Stashed \(files.count) files") { try await $0.stash(message: "", includeUntracked: true, paths: paths) }
                }
                .buttonStyle(.glass)
                Button("Discard…", role: .destructive) { confirmDiscard = true }
                    .buttonStyle(.glass)
                    .disabled(files.contains { $0.area == .conflicted })
            }
        }
        .confirmationDialog("Discard changes to \(files.count) files?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) {
                let picked = files
                clear()
                store.discard(picked, in: repo.id)
            }
        } message: {
            Text("You can undo this right after.")
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !unstaged.isEmpty { parts.append("\(unstaged.count) unstaged") }
        if !staged.isEmpty { parts.append("\(staged.count) staged") }
        let adds = files.reduce(0) { $0 + $1.additions }, dels = files.reduce(0) { $0 + $1.deletions }
        if adds + dels > 0 { parts.append("+\(adds) −\(dels)") }
        return parts.joined(separator: " · ") + "\nSpace stages / unstages the selection, ⌫ discards it."
    }

    private func run(_ label: String, success: String? = nil, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        clear()
        Task { await store.perform(repo.id, label, success: success, op) }
    }
}
