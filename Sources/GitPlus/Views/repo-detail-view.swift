import SwiftUI

struct RepoDetailView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry

    private enum Tab: String, CaseIterable { case history = "History", reviews = "Reviews" }
    @State private var tab = Tab.history

    private var status: RepoStatus? { store.statuses[repo.id] }
    private var provider: GitProvider { status?.remote?.provider ?? .other }

    var body: some View {
        Group {
            switch tab {
            case .history: CommitHistoryView(repo: repo, remote: status?.remote)
            case .reviews: PullRequestsView(repoURL: repo.url, provider: provider)
            }
        }
        .navigationTitle(repo.name)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    Text("History").tag(Tab.history)
                    Text(provider.reviewNoun).tag(Tab.reviews)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup {
                Button { Task { await store.fetch([repo.id]) } } label: { Label("Fetch", systemImage: "arrow.down.circle") }
                    .disabled(store.busy.contains(repo.id))
                Button { Task { await store.pull([repo.id]) } } label: { Label("Pull", systemImage: "arrow.down.to.line") }
                    .disabled(store.busy.contains(repo.id))
                if let web = status?.remote?.webURL {
                    Button { NSWorkspace.shared.open(web) } label: { Label("Open on Web", systemImage: "safari") }
                }
            }
        }
    }

    private var subtitle: String {
        guard let s = status else { return repo.path }
        var parts = [s.branch]
        if s.ahead > 0 { parts.append("↑\(s.ahead)") }
        if s.behind > 0 { parts.append("↓\(s.behind)") }
        if s.changedFiles > 0 { parts.append("\(s.changedFiles) changed") }
        return parts.joined(separator: "  ")
    }
}

/// Commit list (multi-select → range diff) with branch filter and message search.
struct CommitHistoryView: View {
    let repo: RepoEntry
    let remote: RemoteInfo?

    private static let allBranches = "‹all branches›"
    private static let head = "HEAD"

    @State private var branches: [String] = []
    @State private var ref = CommitHistoryView.head
    @State private var search = ""
    @State private var commits: [Commit] = []
    @State private var selection = Set<String>()
    @State private var error: String?

    private var git: GitService { GitService(repo: repo.url) }

    /// Selected commits ordered newest first (matching log order).
    private var selectedCommits: [Commit] { commits.filter { selection.contains($0.hash) } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Picker("Branch", selection: $ref) {
                        Text("HEAD").tag(Self.head)
                        Text("All branches").tag(Self.allBranches)
                        Divider()
                        ForEach(branches, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    TextField("Search messages", text: $search).textFieldStyle(.roundedBorder)
                }
                .padding(8)
                Divider()
                List(commits, selection: $selection) { CommitRowView(commit: $0, repoName: nil) }
                    .overlay { if let error { Text(error).foregroundStyle(.red).padding() } }
                Text("⌘-click or ⇧-click to diff a range of commits")
                    .font(.caption2).foregroundStyle(.secondary).padding(4)
            }
            .frame(minWidth: 320, idealWidth: 420)

            Group {
                if let target = DiffTarget.range(selectedCommits) {
                    CommitDiffView(repoURL: repo.url, target: target, remote: selection.count == 1 ? remote : nil).id(target)
                } else {
                    ContentUnavailableView("Select a commit", systemImage: "arrow.left.and.right.text.vertical")
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { branches = (try? await git.branches()) ?? [] }
        .task(id: "\(ref)|\(search)") { await load() }
    }

    private func load() async {
        // Debounce typing in the search field.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            commits = try await git.log(ref: ref == Self.allBranches ? nil : ref, allRefs: ref == Self.allBranches, search: search)
            error = nil
        } catch {
            commits = []
            self.error = error.localizedDescription
        }
    }
}
