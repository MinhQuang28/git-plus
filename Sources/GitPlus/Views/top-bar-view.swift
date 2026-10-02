import SwiftUI

/// GitHub Desktop–style top bar: repository/group picker, branch picker, fetch/pull/push, reviews.
struct TopBarView: View {
    @Environment(WorkspaceStore.self) private var store
    @Binding var selection: SidebarSelection?

    @State private var showRepoPicker = false
    @State private var showBranchPicker = false
    @State private var showReviews = false

    private var repo: RepoEntry? {
        if case .repo(let id) = selection { return store.repo(id) }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            TopBarButton(icon: repo == nil ? "folder" : "book.closed", caption: repo == nil ? "Current Group" : "Current Repository",
                         title: title, showsChevron: true, width: 280) { showRepoPicker.toggle() }
                .help("Repositories and groups (⌘T)")
                .popover(isPresented: $showRepoPicker, arrowEdge: .bottom) {
                    RepositoryPickerView(selection: $selection, isPresented: $showRepoPicker)
                }
            if let repo {
                let status = store.statuses[repo.id]
                TopBarButton(icon: "arrow.triangle.branch", caption: "Current Branch", title: status?.branch ?? "–",
                             showsChevron: true, width: 260) { showBranchPicker.toggle() }
                    .help("Branches (⌘B)")
                    .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) {
                        BranchPickerView(repo: repo, isPresented: $showBranchPicker)
                    }
                SyncButton(repo: repo, status: status)
                if let provider = status?.remote?.provider, provider != .other {
                    TopBarButton(icon: "arrow.triangle.pull", caption: provider.cliName.map { "via \($0)" } ?? "",
                                 title: provider.reviewNoun, showsChevron: false, width: 190) { showReviews.toggle() }
                        .popover(isPresented: $showReviews, arrowEdge: .bottom) {
                            PullRequestsView(repoURL: repo.url, provider: provider).frame(width: 860, height: 460)
                        }
                }
            } else if selection != nil {
                let ids = groupRepoIDs
                let busy = ids.contains { store.busy.contains($0) }
                TopBarButton(icon: "arrow.triangle.2.circlepath", caption: "\(ids.count) repositories", title: "Fetch all",
                             showsChevron: false, width: 220, isBusy: busy) { Task { await store.fetch(ids) } }
                    .disabled(ids.isEmpty || busy)
                TopBarButton(icon: "arrow.down.to.line", caption: "fast-forward only", title: "Pull all",
                             showsChevron: false, width: 200) { Task { await store.pull(ids) } }
                    .disabled(ids.isEmpty || busy)
            }
            Spacer(minLength: 0)
            if let repo { OpenInMenu(repo: repo).padding(.trailing, 12) }
        }
        .frame(height: 52)
        .onReceive(NotificationCenter.default.publisher(for: .showRepositoryPicker)) { _ in showRepoPicker = true }
        .onReceive(NotificationCenter.default.publisher(for: .showBranchPicker)) { _ in if repo != nil { showBranchPicker = true } }
        .background(Theme.barBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.barDivider).frame(height: 1) }
    }

    private var title: String {
        switch selection {
        case .repo(let id): store.repo(id)?.name ?? "Select a repository"
        case .group(let id): store.group(id)?.name ?? "Select a repository"
        case .ungrouped: "Ungrouped"
        case nil: "Select a repository"
        }
    }

    private var groupRepoIDs: [UUID] {
        switch selection {
        case .group(let id): store.repos(in: id).map(\.id)
        case .ungrouped: store.repos(in: nil).map(\.id)
        default: []
        }
    }
}

struct TopBarButton: View {
    let icon: String
    let caption: String
    let title: String
    let showsChevron: Bool
    let width: CGFloat
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if isBusy { ProgressView().controlSize(.small) } else { Image(systemName: icon).symbolRenderingMode(.hierarchical) }
                }
                .font(.system(size: 16))
                .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption).font(.system(size: 11)).foregroundStyle(Theme.barSecondaryText)
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if showsChevron { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
            }
            .padding(.horizontal, 14)
            .frame(width: width, height: 52)
            .background(hovering && isEnabled ? Theme.barHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.barText)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.12), value: hovering)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.barDivider).frame(width: 1) }
    }
}

/// Fetch → Pull (behind) → Push (ahead / no upstream), like GitHub Desktop.
struct SyncButton: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let status: RepoStatus?

    var body: some View {
        let busy = store.busy.contains(repo.id)
        TopBarButton(icon: icon, caption: caption, title: title, showsChevron: false, width: 250, isBusy: busy) {
            Task {
                if let s = status, s.behind > 0 { await store.pull([repo.id]) }
                else if let s = status, s.ahead > 0 || (s.upstream == nil && s.remote != nil) { await store.push(repo.id) }
                else { await store.fetch([repo.id]) }
            }
        }
        .disabled(busy)
    }

    private var remoteName: String { status?.upstream?.split(separator: "/").first.map(String.init) ?? "origin" }

    private var title: String {
        guard let s = status else { return "Fetch origin" }
        if s.behind > 0 { return "Pull \(remoteName)  ↓\(s.behind)" }
        if s.ahead > 0 { return "Push \(remoteName)  ↑\(s.ahead)" }
        if s.upstream == nil, s.remote != nil { return "Publish branch" }
        return "Fetch \(remoteName)"
    }

    private var icon: String {
        guard let s = status else { return "arrow.triangle.2.circlepath" }
        if s.behind > 0 { return "arrow.down" }
        if s.ahead > 0 || (s.upstream == nil && s.remote != nil) { return "arrow.up" }
        return "arrow.triangle.2.circlepath"
    }

    private var caption: String {
        guard let date = status?.lastFetched else { return "Never fetched" }
        return "Last fetched \(RelativeTime.string(date))"
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
