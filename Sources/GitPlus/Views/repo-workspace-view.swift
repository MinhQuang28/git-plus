import AppKit
import SwiftUI

/// GitHub Desktop layout for one repository: [Changes | History] column + main content.
struct RepoWorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry

    enum Tab: String { case changes, history }
    @AppStorage("repoTab") private var tab = Tab.history

    @State private var selectedCommits: [Commit] = []
    @State private var changes: [ChangedFile] = []
    @State private var selectedChange: ChangedFile.ID?
    @State private var checked = Set<String>()
    @State private var activationTick = 0

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }
    private var remote: RemoteInfo? { store.statuses[repo.id]?.remote }

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 300, range: 240...480) {
                VStack(spacing: 0) {
                    PaneTabs(tabs: [("Changes", changes.isEmpty ? nil : changes.count), ("History", nil)],
                             selected: tab == .changes ? 0 : 1) { tab = $0 == 0 ? .changes : .history }
                    switch tab {
                    case .changes:
                        ChangesPaneView(repo: repo, files: changes, selection: $selectedChange, checked: $checked)
                    case .history:
                        HistoryPaneView(repo: repo, remote: remote, selected: $selectedCommits)
                    }
                }
                .background(Theme.paneBackground)
            }
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(revision)|\(activationTick)") { await loadChanges() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            activationTick += 1
            Task { await store.refreshStatus([repo.id]) }
        }
    }

    @ViewBuilder private var main: some View {
        switch tab {
        case .changes:
            if let file = changes.first(where: { $0.id == selectedChange }) {
                FileDiffView(source: .workingTree(git), file: file, reloadKey: revision &+ activationTick).id(file.id)
            } else {
                ContentUnavailableView("No local changes", systemImage: "checkmark.circle")
            }
        case .history:
            if let target = DiffTarget.range(selectedCommits) {
                CommitDetailView(repoURL: repo.url, target: target,
                                 commit: selectedCommits.count == 1 ? selectedCommits.first : nil, remote: remote)
            } else {
                ContentUnavailableView("Select a commit", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func loadChanges() async {
        let loaded = (try? await git.workingChanges()) ?? []
        // Newly appearing files are checked by default; unchecked ones stay unchecked.
        let newIDs = Set(loaded.map(\.id)).subtracting(changes.map(\.id))
        checked = checked.intersection(loaded.map(\.id)).union(newIDs)
        changes = loaded
        if !loaded.contains(where: { $0.id == selectedChange }) { selectedChange = loaded.first?.id }
    }
}

/// Underlined tab strip ("Changes  |  History").
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
                        if let badge = tabs[i].badge {
                            Text("\(badge)").font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.secondary.opacity(0.3)))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selected == i ? Color.accentColor : .clear).frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                if i < tabs.count - 1 { Rectangle().fill(Theme.separator).frame(width: 1, height: 36) }
            }
        }
        .background(Theme.headerBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }
}
