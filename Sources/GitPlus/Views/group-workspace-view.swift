import SwiftUI

/// Group layout: [Repositories | Activity] column + dashboard table or commit detail.
struct GroupWorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    let groupID: UUID?
    @Binding var selection: SidebarSelection?

    @AppStorage("groupTab") private var tab = 0
    let title: String
    @State private var activity: [RepoCommit] = []
    @State private var selectedActivity: RepoCommit.ID?
    @State private var isLoading = false

    private var repos: [RepoEntry] { store.repos(in: groupID) }
    private var revisionKey: String { repos.map { "\($0.id)\(store.revisions[$0.id] ?? 0)" }.joined() }

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                SwitcherColumn {
                    if tab == 1 { activityList } else { repoList }
                }
            }
            main.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(title)
        .toolbar(removing: .title)
        .toolbar { groupToolbar }
        .task(id: revisionKey) { await loadActivity() }
    }

    @ToolbarContentBuilder private var groupToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $tab) {
                Text("Repositories").tag(0)
                Text("Activity").tag(1)
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let ids = repos.map(\.id)
            let busy = ids.contains { store.busy.contains($0) }
            Button { Task { await store.fetch(ids) } } label: {
                Label("Fetch All", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon)
            }
            .disabled(ids.isEmpty || busy)
            Button { Task { await store.pull(ids) } } label: {
                Label("Pull All", systemImage: "arrow.down.circle").labelStyle(.titleAndIcon)
            }
            .disabled(ids.isEmpty || busy)
            .help("Fast-forward every repository in this group")
        }
    }

    private var repoList: some View {
        List(repos) { repo in
            Button { selection = .repo(repo.id) } label: {
                RepoRowView(repo: repo, status: store.statuses[repo.id], isBusy: store.busy.contains(repo.id))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { RepoContextMenu(repo: repo, selection: $selection) }
        }
        .listStyle(.inset)
    }

    private var activityList: some View {
        List(activity, selection: $selectedActivity) { item in
            CommitListRow(commit: item.commit, repoName: item.repoName).listRowSeparator(.visible)
        }
        .listStyle(.plain)
        .overlay { if isLoading && activity.isEmpty { ProgressView() } }
    }

    @ViewBuilder private var main: some View {
        if tab == 0 {
            GroupDashboardTable(repos: repos, selection: $selection)
        } else if let item = activity.first(where: { $0.id == selectedActivity }), let repo = store.repo(item.repoID) {
            CommitDetailView(repoURL: repo.url, target: .commit(item.commit), commit: item.commit, remote: store.statuses[repo.id]?.remote)
                .id(item.id)
        } else {
            ContentUnavailableView("Select a commit", systemImage: "clock.arrow.circlepath",
                                   description: Text("Recent commits from every repository in this group."))
        }
    }

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }
        var merged: [RepoCommit] = []
        await withTaskGroup(of: [RepoCommit].self) { group in
            for repo in repos {
                group.addTask {
                    let log = (try? await GitService(repo: repo.url).log(allRefs: true, limit: 30)) ?? []
                    return log.map { RepoCommit(repoID: repo.id, repoName: repo.name, commit: $0) }
                }
            }
            for await part in group { merged += part }
        }
        activity = merged.sorted { $0.commit.date > $1.commit.date }
    }
}

/// Status of every repo in a group; double-click opens the repo.
struct GroupDashboardTable: View {
    @Environment(WorkspaceStore.self) private var store
    let repos: [RepoEntry]
    @Binding var selection: SidebarSelection?
    @State private var tableSelection: RepoEntry.ID?

    var body: some View {
        Table(repos, selection: $tableSelection) {
            TableColumn("Repository") { repo in
                HStack {
                    ProviderIcon(provider: store.statuses[repo.id]?.remote?.provider)
                    Text(repo.name).fontWeight(.medium)
                    if store.busy.contains(repo.id) { ProgressView().controlSize(.small) }
                }
            }
            TableColumn("Branch") { Text(store.statuses[$0.id]?.branch ?? "–") }
            TableColumn("Sync") { repo in
                if let s = store.statuses[repo.id] {
                    if s.upstream == nil { Text("not published").foregroundStyle(.secondary) } else { SyncBadge(status: s) }
                }
            }
            .width(100)
            TableColumn("Changes") { repo in
                let n = store.statuses[repo.id]?.changedFiles ?? 0
                Text(n == 0 ? "clean" : "\(n) files").foregroundStyle(n == 0 ? .secondary : .primary)
            }
            .width(80)
            TableColumn("Last fetched") { repo in
                Text(store.statuses[repo.id]?.lastFetched.map(RelativeTime.string) ?? "never").foregroundStyle(.secondary)
            }
            .width(130)
            TableColumn("Remote") { Text(store.statuses[$0.id]?.remote?.groupKey ?? "–").foregroundStyle(.secondary) }
        }
        .contextMenu(forSelectionType: RepoEntry.ID.self) { ids in
            if let id = ids.first, let repo = store.repo(id) {
                Button("Open") { selection = .repo(id) }
                RepoContextMenu(repo: repo, selection: $selection)
            }
        } primaryAction: { ids in
            if let id = ids.first { selection = .repo(id) }
        }
    }
}
