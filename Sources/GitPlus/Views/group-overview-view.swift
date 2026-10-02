import SwiftUI

/// Dashboard for a group: status table for every repo + bulk fetch/pull + merged activity.
struct GroupOverviewView: View {
    @Environment(WorkspaceStore.self) private var store
    let groupID: UUID?
    let title: String

    private enum Tab: String, CaseIterable { case repositories = "Repositories", activity = "Activity" }
    @State private var tab = Tab.repositories

    private var repos: [RepoEntry] { store.repos(in: groupID) }
    private var ids: [UUID] { repos.map(\.id) }

    var body: some View {
        Group {
            switch tab {
            case .repositories: repoTable
            case .activity: GroupActivityView(repos: repos)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(repos.count) repositories")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                Button { Task { await store.refreshStatus(ids) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { Task { await store.fetch(ids) } } label: { Label("Fetch All", systemImage: "arrow.down.circle") }
                Button { Task { await store.pull(ids) } } label: { Label("Pull All", systemImage: "arrow.down.to.line") }
            }
        }
    }

    private var repoTable: some View {
        Table(repos) {
            TableColumn("Repository") { repo in
                HStack {
                    ProviderIcon(provider: store.statuses[repo.id]?.remote?.provider)
                    Text(repo.name)
                    if store.busy.contains(repo.id) { ProgressView().controlSize(.small) }
                }
            }
            TableColumn("Branch") { Text(store.statuses[$0.id]?.branch ?? "–") }
            TableColumn("Sync") { repo in
                if let s = store.statuses[repo.id] {
                    if s.upstream == nil { Text("no upstream").foregroundStyle(.secondary) } else { SyncBadge(status: s) }
                }
            }
            .width(90)
            TableColumn("Changes") { repo in
                let n = store.statuses[repo.id]?.changedFiles ?? 0
                Text(n == 0 ? "clean" : "\(n) files").foregroundStyle(n == 0 ? .secondary : .primary)
            }
            .width(80)
            TableColumn("Remote") { Text(store.statuses[$0.id]?.remote?.groupKey ?? "–").foregroundStyle(.secondary) }
            TableColumn("Path") { Text($0.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
        }
    }
}

/// Recent commits from every repo in a group, merged into one timeline.
struct GroupActivityView: View {
    let repos: [RepoEntry]
    @State private var commits: [RepoCommit] = []
    @State private var selection: RepoCommit.ID?
    @State private var isLoading = false
    @State private var perRepoLimit = 30

    private var selected: RepoCommit? { commits.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            List(commits, selection: $selection) { item in
                CommitRowView(commit: item.commit, repoName: item.repoName)
            }
            .overlay { if isLoading && commits.isEmpty { ProgressView() } }
            .frame(minWidth: 320, idealWidth: 420)

            Group {
                if let selected, let repo = repos.first(where: { $0.id == selected.repoID }) {
                    CommitDiffView(repoURL: repo.url, target: .commit(selected.commit)).id(selected.id)
                } else {
                    ContentUnavailableView("Select a commit", systemImage: "arrow.left.and.right.text.vertical")
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: repos.map(\.id)) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let limit = perRepoLimit
        var merged: [RepoCommit] = []
        await withTaskGroup(of: [RepoCommit].self) { group in
            for repo in repos {
                group.addTask {
                    let log = (try? await GitService(repo: repo.url).log(allRefs: true, limit: limit)) ?? []
                    return log.map { RepoCommit(repoID: repo.id, repoName: repo.name, commit: $0) }
                }
            }
            for await part in group { merged += part }
        }
        commits = merged.sorted { $0.commit.date > $1.commit.date }
    }
}
