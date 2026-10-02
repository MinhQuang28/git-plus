import SwiftUI

enum RepoTab: Int, CaseIterable {
    case changes, history, stashes

    var title: String {
        switch self {
        case .changes: "Changes"
        case .history: "History"
        case .stashes: "Stashes"
        }
    }
}

/// Toolbar for a repository window (rendered as Liquid Glass by the system).
struct RepoToolbar: ToolbarContent {
    let repo: RepoEntry
    let status: RepoStatus?
    @Binding var tab: RepoTab
    let changeCount: Int
    let stashCount: Int

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BranchToolbarButton(repo: repo, branch: status?.branch ?? "–")
        }
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $tab) {
                ForEach(RepoTab.allCases, id: \.self) { t in
                    Text(label(t)).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .help("⌘1 Changes · ⌘2 History · ⌘3 Stashes")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            SyncToolbarButton(repo: repo, status: status)
            if let provider = status?.remote?.provider, provider != .other {
                ReviewsToolbarButton(repoURL: repo.url, provider: provider)
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { OpenInMenu(repo: repo) }
    }

    private func label(_ t: RepoTab) -> String {
        switch t {
        case .changes: changeCount > 0 ? "Changes \(changeCount)" : "Changes"
        case .stashes: stashCount > 0 ? "Stashes \(stashCount)" : "Stashes"
        case .history: "History"
        }
    }
}

/// Current branch; opens the branch list (⌘B).
struct BranchToolbarButton: View {
    let repo: RepoEntry
    let branch: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Label(branch, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon)
        }
        .help("Switch, create, merge or delete branches (⌘B)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BranchPickerView(repo: repo, isPresented: $isPresented)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBranchPicker)) { _ in isPresented = true }
    }
}

/// Fetch → Pull (behind) → Push (ahead) → Publish (no upstream), like GitHub Desktop.
struct SyncToolbarButton: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let status: RepoStatus?

    var body: some View {
        let busy = store.busy.contains(repo.id)
        Button {
            Task {
                if let s = status, s.behind > 0 { await store.pull([repo.id]) }
                else if let s = status, s.ahead > 0 || (s.upstream == nil && s.remote != nil) { await store.push(repo.id) }
                else { await store.fetch([repo.id]) }
            }
        } label: {
            if busy {
                Label { Text("Syncing…") } icon: { ProgressView().controlSize(.small) }.labelStyle(.titleAndIcon)
            } else {
                Label(title, systemImage: icon).labelStyle(.titleAndIcon)
            }
        }
        .disabled(busy)
        .help(status?.lastFetched.map { "Last fetched \(RelativeTime.string($0))" } ?? "Never fetched")
    }

    private var remoteName: String { status?.upstream?.split(separator: "/").first.map(String.init) ?? "origin" }

    private var title: String {
        guard let s = status else { return "Fetch" }
        if s.behind > 0 { return "Pull \(s.behind)" }
        if s.ahead > 0 { return "Push \(s.ahead)" }
        if s.upstream == nil, s.remote != nil { return "Publish" }
        return "Fetch \(remoteName)"
    }

    private var icon: String {
        guard let s = status else { return "arrow.triangle.2.circlepath" }
        if s.behind > 0 { return "arrow.down.circle" }
        if s.ahead > 0 || (s.upstream == nil && s.remote != nil) { return "arrow.up.circle" }
        return "arrow.triangle.2.circlepath"
    }
}

struct ReviewsToolbarButton: View {
    let repoURL: URL
    let provider: GitProvider
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: { Label(provider.reviewNoun, systemImage: "arrow.triangle.pull") }
            .help("\(provider.reviewNoun) via \(provider.cliName ?? "")")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PullRequestsView(repoURL: repoURL, provider: provider).frame(width: 860, height: 460)
            }
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .full
        return f
    }()

    /// "just now", "21 minutes ago", "yesterday", "11 days ago".
    static func string(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return "just now" }
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
