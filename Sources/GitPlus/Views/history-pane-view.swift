import SwiftUI

/// Left pane "History" tab: branch compare field + commit list with graph (multi-select → range diff).
/// History loads in pages as you scroll; the search box queries git (`author:` and `path:` narrow it down).
struct HistoryPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let remote: RemoteInfo?
    @Binding var selected: [Commit]

    private enum CompareSide: String { case behind, ahead }
    private static let pageSize = 200

    @State private var commits: [Commit] = []
    @State private var graph: [GraphRow] = []
    /// Lanes to reserve (computed with the graph, not per render).
    @State private var graphWidth = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false
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
    @AppStorage("historyGraph") private var showGraph = true
    @State private var query = ""
    @State private var isSearching = false

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }
    private var parsedQuery: HistoryQuery { HistoryQuery(parsing: query) }
    /// The graph only makes sense for an unfiltered, uncompared history.
    private var graphVisible: Bool { showGraph && compareBranch == nil && parsedQuery.isEmpty && graph.count == commits.count }

    var body: some View {
        VStack(spacing: 0) {
            compareField
            Divider()
            // Suggestions appear only while typing, so an auto-focused field never hides the history.
            if compareFocused && compareBranch == nil && !compareText.isEmpty {
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
        .task(id: "\(revision)|\(compareBranch ?? "")|\(side.rawValue)|\(allBranches)|\(query)") {
            if !query.isEmpty {
                isSearching = true
                try? await Task.sleep(for: .milliseconds(300))   // debounce typing
                guard !Task.isCancelled else { return }
            }
            await load()
            isSearching = false
        }
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
                    .onExitCommand { compareFocused = false; compareText = "" }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(Theme.headerBackground))
        .overlay(RoundedRectangle(cornerRadius: Radius.s).stroke(Theme.separator))
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
                if isSearching {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                }
                TextField("Search  ·  author:name  path:dir/", text: $query).textFieldStyle(.plain).font(.callout)
                    .help("Searches commit messages and authors (or a SHA). Add author:… or path:… to narrow it down.")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(Theme.headerBackground))
            .overlay(Capsule().stroke(Theme.separator))
            OptionChip(title: "All", symbol: "arrow.triangle.branch", isOn: $allBranches)
                .help("Show commits from all branches")
            OptionChip(title: "Graph", symbol: "point.3.connected.trianglepath.dotted", isOn: $showGraph)
                .help("Show the commit graph")
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private var commitList: some View {
        let showsGraph = graphVisible
        let width = graphWidth
        return List(selection: $selection) {
            ForEach(Array(commits.enumerated()), id: \.element.hash) { index, commit in
                HStack(spacing: Spacing.xs) {
                    if showsGraph { CommitGraphCell(row: graph[index], lanes: width) }
                    CommitListRow(commit: commit, showsRefs: allBranches || showsGraph, isHead: commit.hash == headHash)
                }
                .fixedSize(horizontal: false, vertical: true)
                .listRowInsets(showsGraph ? EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8) : EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 8))
                .listRowSeparator(showsGraph ? .hidden : .visible)
                .tag(commit.hash)
                .onAppear { if index == commits.count - 1 { Task { await loadMore() } } }
            }
            if isLoadingMore {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: String.self) { hashes in
            if hashes.count == 1, let hash = hashes.first, let commit = commits.first(where: { $0.hash == hash }) {
                CommitContextMenu(repo: repo, commit: commit,
                                  canReset: compareBranch == nil && hash != headHash,
                                  isHead: hash == headHash,
                                  remote: remote) { request = $0 }
            }
        }
        .overlay {
            if commits.isEmpty && !isSearching {
                Text(!query.isEmpty ? "No commits match “\(query)”" : compareBranch == nil ? "No commits" : "Nothing to show")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ref: String? {
        switch (compareBranch, side) {
        case (nil, _): nil
        case (let b?, .behind): "HEAD..\(b)"
        case (let b?, .ahead): "\(b)..HEAD"
        }
    }

    private func load() async {
        if let compareBranch { counts = await git.aheadBehind(compareBranch) }
        let all = compareBranch == nil && allBranches
        let q = parsedQuery
        let loaded: [Commit]
        if q.isEmpty {
            loaded = (try? await git.log(ref: ref, allRefs: all, limit: Self.pageSize)) ?? []
            hasMore = loaded.count == Self.pageSize
        } else {
            loaded = (try? await git.search(q, ref: ref, allRefs: all)) ?? []
            hasMore = false
        }
        commits = loaded
        setGraph(q.isEmpty && compareBranch == nil ? CommitGraph.layout(loaded) : [])
        // Keep the selection across refreshes when possible; otherwise select the newest commit.
        let kept = selection.filter { hash in loaded.contains { $0.hash == hash } }
        selection = kept.isEmpty ? Set(loaded.prefix(1).map(\.hash)) : kept
        selected = loaded.filter { selection.contains($0.hash) }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, parsedQuery.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let all = compareBranch == nil && allBranches
        let page = (try? await git.log(ref: ref, allRefs: all, limit: Self.pageSize, skip: commits.count)) ?? []
        hasMore = page.count == Self.pageSize
        let known = Set(commits.map(\.hash))
        commits += page.filter { !known.contains($0.hash) }
        if compareBranch == nil { setGraph(CommitGraph.layout(commits)) }
    }

    private func setGraph(_ rows: [GraphRow]) {
        graph = rows
        graphWidth = min(rows.map(\.width).max() ?? 1, 8)
    }
}

/// Graph lanes for one commit row (see `CommitGraph`).
struct CommitGraphCell: View {
    let row: GraphRow
    let lanes: Int
    static let laneWidth: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let w = Self.laneWidth
            func x(_ lane: Int) -> CGFloat { CGFloat(min(lane, lanes - 1)) * w + w / 2 }
            func line(_ from: CGPoint, _ to: CGPoint, color: Color) {
                var path = Path()
                path.move(to: from)
                if from.x == to.x {
                    path.addLine(to: to)
                } else {
                    let dy = (to.y - from.y) * 0.6
                    path.addCurve(to: to, control1: CGPoint(x: from.x, y: from.y + dy), control2: CGPoint(x: to.x, y: to.y - dy))
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            for s in row.top { line(CGPoint(x: x(s.from), y: 0), CGPoint(x: x(s.to), y: mid), color: Theme.lane(s.from)) }
            for s in row.bottom { line(CGPoint(x: x(s.from), y: mid), CGPoint(x: x(s.to), y: size.height), color: Theme.lane(s.to)) }
            let r: CGFloat = row.isMerge ? 3.5 : 4
            let dot = Path(ellipseIn: CGRect(x: x(row.node) - r, y: mid - r, width: r * 2, height: r * 2))
            if row.isMerge {
                context.fill(dot, with: .color(Theme.paneBackground))
                context.stroke(dot, with: .color(Theme.lane(row.node)), lineWidth: 1.8)
            } else {
                context.fill(dot, with: .color(Theme.lane(row.node)))
            }
        }
        .frame(width: CGFloat(lanes) * Self.laneWidth)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
