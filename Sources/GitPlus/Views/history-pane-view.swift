import SwiftUI

/// Left pane "History" tab: branch compare field + commit list (multi-select → range diff).
struct HistoryPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let remote: RemoteInfo?
    @Binding var selected: [Commit]

    private enum CompareSide: String { case behind, ahead }

    @State private var commits: [Commit] = []
    @State private var selection = Set<String>()
    @State private var headHash: String?
    @State private var branches = BranchList()
    @State private var compareText = ""
    @State private var compareBranch: String?
    @State private var side = CompareSide.behind
    @State private var counts = (ahead: 0, behind: 0)
    @State private var request: CommitRequest?
    @FocusState private var compareFocused: Bool
    @AppStorage("historyAllBranches") private var allBranches = false
    @State private var query = ""

    /// Local filter on subject, author, email or SHA prefix.
    private var visible: [Commit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commits }
        return commits.filter {
            $0.subject.localizedCaseInsensitiveContains(q) || $0.author.localizedCaseInsensitiveContains(q)
                || $0.email.localizedCaseInsensitiveContains(q) || $0.hash.hasPrefix(q.lowercased())
        }
    }

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            compareField
            Divider()
            if compareFocused && compareBranch == nil {
                branchSuggestions
            } else {
                if let compareBranch { compareTabs(compareBranch) } else { viewOptions }
                commitList
            }
        }
        .task(id: revision) {
            branches = (try? await git.branches()) ?? BranchList()
            headHash = await git.headHash()
        }
        .task(id: "\(revision)|\(compareBranch ?? "")|\(side.rawValue)|\(allBranches)") { await load() }
        .onChange(of: selection) { selected = commits.filter { selection.contains($0.hash) } }
        .modifier(CommitRequestPresenter(repo: repo, request: $request))
    }

    private var compareField: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
            if let compareBranch {
                Text(compareBranch).lineLimit(1)
                Spacer()
                Button { self.compareBranch = nil; compareText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            } else {
                TextField("Select Branch to Compare…", text: $compareText)
                    .textFieldStyle(.plain)
                    .focused($compareFocused)
                    .onExitCommand { compareFocused = false }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.headerBackground))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
        .padding(8)
    }

    private var branchSuggestions: some View {
        let all = branches.local.filter { $0 != branches.current } + branches.remote
        let matches = all.filter { compareText.isEmpty || $0.localizedCaseInsensitiveContains(compareText) }
        return List(matches, id: \.self) { name in
            Button {
                compareBranch = name
                side = .behind
                compareFocused = false
            } label: {
                Label(name, systemImage: branches.local.contains(name) ? "arrow.triangle.branch" : "cloud")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func compareTabs(_ branch: String) -> some View {
        Picker("", selection: $side) {
            Text("Behind (\(counts.behind))").tag(CompareSide.behind)
            Text("Ahead (\(counts.ahead))").tag(CompareSide.ahead)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8).padding(.bottom, 6)
        .help(side == .behind ? "Commits in \(branch) not in your branch" : "Commits in your branch not in \(branch)")
    }

    private var viewOptions: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Filter message, author, SHA", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(Theme.headerBackground))
            .overlay(Capsule().stroke(Theme.separator))
            OptionChip(title: "All", symbol: "arrow.triangle.branch", isOn: $allBranches)
                .help("Show commits from all branches")
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private var commitList: some View {
        List(visible, selection: $selection) { commit in
            CommitListRow(commit: commit, showsRefs: allBranches).listRowSeparator(.visible)
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: String.self) { hashes in
            if hashes.count == 1, let hash = hashes.first, let commit = commits.first(where: { $0.hash == hash }) {
                CommitContextMenu(repo: repo, commit: commit,
                                  canReset: compareBranch == nil && hash != headHash,
                                  remote: remote) { request = $0 }
            }
        }
        .overlay {
            if visible.isEmpty {
                Text(!query.isEmpty ? "No commits match “\(query)”" : compareBranch == nil ? "No commits" : "Nothing to show")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        let ref: String? = switch (compareBranch, side) {
        case (nil, _): nil
        case (let b?, .behind): "HEAD..\(b)"
        case (let b?, .ahead): "\(b)..HEAD"
        }
        if let compareBranch { counts = await git.aheadBehind(compareBranch) }
        let all = compareBranch == nil && allBranches
        let loaded = (try? await git.log(ref: ref, allRefs: all)) ?? []
        commits = loaded
        // Keep the selection across refreshes when possible; otherwise select the newest commit.
        let kept = selection.filter { hash in loaded.contains { $0.hash == hash } }
        selection = kept.isEmpty ? Set(loaded.prefix(1).map(\.hash)) : kept
        selected = loaded.filter { selection.contains($0.hash) }
    }
}
