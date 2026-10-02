import AppKit
import SwiftUI

/// Layout for one repository: [Changes | History | Stashes] column + main content.
struct RepoWorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry

    enum Tab: Int { case changes, history, stashes }
    @AppStorage("repoTab") private var tab = Tab.history

    @State private var selectedCommits: [Commit] = []
    @State private var tree = WorkingTree()
    @State private var selectedChange: ChangedFile.ID?
    @State private var stashes: [StashEntry] = []
    @State private var selectedStash: StashEntry.ID?
    @State private var activationTick = 0
    @AppStorage("autoFetch") private var autoFetch = true

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }
    private var status: RepoStatus? { store.statuses[repo.id] }

    var body: some View {
        VStack(spacing: 0) {
            if let op = status?.operation {
                OperationBannerView(repo: repo, operation: op, conflicts: status?.conflicts ?? 0)
            }
            HStack(spacing: 0) {
                ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                    VStack(spacing: 0) {
                        PaneTabs(tabs: [("Changes", tree.isEmpty ? nil : tree.count), ("History", nil),
                                        ("Stashes", stashes.isEmpty ? nil : stashes.count)],
                                 selected: tab.rawValue) { tab = Tab(rawValue: $0) ?? .history }
                        switch tab {
                        case .changes: ChangesPaneView(repo: repo, tree: tree, selection: $selectedChange)
                        case .history: HistoryPaneView(repo: repo, remote: status?.remote, selected: $selectedCommits)
                        case .stashes: StashListView(stashes: stashes, selection: $selectedStash)
                        }
                    }
                    .background(Theme.paneBackground)
                }
                main.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                ContentUnavailableView(tree.isEmpty ? "No local changes" : "Select a file",
                                       systemImage: tree.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass")
            }
        case .history:
            if let target = DiffTarget.range(selectedCommits) {
                CommitDetailView(repoURL: repo.url, target: target,
                                 commit: selectedCommits.count == 1 ? selectedCommits.first : nil, remote: status?.remote)
            } else {
                ContentUnavailableView("Select a commit", systemImage: "clock.arrow.circlepath")
            }
        case .stashes:
            if let entry = stashes.first(where: { $0.id == selectedStash }) {
                StashDetailView(repo: repo, entry: entry).id(entry.id)
            } else {
                ContentUnavailableView("Select a stash", systemImage: "tray")
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

/// Underlined tab strip ("Changes  |  History  |  Stashes").
struct PaneTabs: View {
    let tabs: [(title: String, badge: Int?)]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button { onSelect(i) } label: {
                    HStack(spacing: 5) {
                        Text(tabs[i].title).font(.system(size: 13, weight: selected == i ? .semibold : .regular))
                            .foregroundStyle(selected == i ? .primary : .secondary)
                        if let badge = tabs[i].badge {
                            Text("\(badge)").font(.system(size: 10, weight: .bold).monospacedDigit())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(selected == i ? Color.accentColor.opacity(0.25) : .secondary.opacity(0.18)))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected == i ? Color.accentColor : .clear).frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
        }
        .background(Theme.headerBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }
}
