import SwiftUI

/// Group overview: filter chips + a grid of repository cards (or the compact table).
struct GroupDashboardView: View {
    @Environment(WorkspaceStore.self) private var store
    let repos: [RepoEntry]
    /// Commits per day over the last 14 days, per repository (computed once per activity load).
    let sparklines: [UUID: [Int]]
    @Binding var selection: SidebarSelection?

    enum Filter: String, CaseIterable {
        case all = "All", changes = "Changes", behind = "Behind", ahead = "Ahead", unpublished = "Unpublished", attention = "Attention"
    }

    @AppStorage("groupLayoutGrid") private var grid = true
    @State private var filter = Filter.all

    private static func passes(_ filter: Filter, _ s: RepoStatus?) -> Bool {
        switch filter {
        case .all: true
        case .changes: (s?.changedFiles ?? 0) > 0
        case .behind: (s?.behind ?? 0) > 0
        case .ahead: (s?.ahead ?? 0) > 0
        case .unpublished: s != nil && s?.upstream == nil
        case .attention: s == nil || s?.operation != nil || (s?.conflicts ?? 0) > 0 || SyncSuggestion(s).needsAttention
        }
    }

    private func matches(_ repo: RepoEntry) -> Bool { Self.passes(filter, store.statuses[repo.id]) }

    /// Every filter's count in one pass over the repositories.
    private func counts() -> [Filter: Int] {
        var result: [Filter: Int] = [:]
        for repo in repos {
            let s = store.statuses[repo.id]
            for f in Filter.allCases where Self.passes(f, s) { result[f, default: 0] += 1 }
        }
        return result
    }

    var body: some View {
        let counts = counts()
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                ForEach(Filter.allCases, id: \.self) { f in
                    let n = counts[f] ?? 0
                    if f == .all || n > 0 {
                        Button { filter = f } label: {
                            HStack(spacing: Spacing.xs) {
                                Text(f.rawValue)
                                Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .appFont(.callout, weight: .medium)
                            .padding(.horizontal, 10).padding(.vertical, Spacing.xs)
                            .background(Capsule().fill(filter == f ? Theme.accent.opacity(0.2) : Theme.headerBackground))
                            .overlay(Capsule().stroke(filter == f ? Theme.accent.opacity(0.6) : Theme.separator))
                            .foregroundStyle(filter == f ? Theme.accent : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == f ? .isSelected : [])
                    }
                }
                Spacer()
                Picker("Layout", selection: $grid) {
                    Label("Cards", systemImage: "square.grid.2x2").labelStyle(.iconOnly).help("Cards").tag(true)
                    Label("Table", systemImage: "list.bullet").labelStyle(.iconOnly).help("Table").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(Spacing.m)
            Divider()
            let visible = repos.filter(matches)
            if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Spacing.m)], spacing: Spacing.m) {
                        ForEach(visible) { repo in
                            // A real button: focusable and operable from the keyboard and VoiceOver.
                            Button { selection = .repo(repo.id) } label: {
                                RepoCard(repo: repo, sparkline: sparklines[repo.id] ?? Self.emptySparkline)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { RepoContextMenu(repo: repo, selection: $selection) }
                        }
                    }
                    .padding(Spacing.m)
                }
                .overlay { if visible.isEmpty { ContentUnavailableView {
                    Label("No \(filter.rawValue) Repositories", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Show All") { filter = .all }
                } } }
            } else {
                GroupDashboardTable(repos: visible, selection: $selection)
            }
        }
    }

    private static let emptySparkline = Array(repeating: 0, count: 14)

    /// Commits per day over the last 14 days for every repository, in one pass over the activity.
    static func sparklines(_ activity: [RepoCommit]) -> [UUID: [Int]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var result: [UUID: [Int]] = [:]
        for item in activity {
            let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: item.commit.date), to: today).day ?? 99
            guard d >= 0 && d < 14 else { continue }
            result[item.repoID, default: emptySparkline][13 - d] += 1
        }
        return result
    }
}

/// One repository in the group overview.
struct RepoCard: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let sparkline: [Int]

    var body: some View {
        let status = store.statuses[repo.id]
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ProviderIcon(provider: status?.remote?.provider)
                Text(repo.name).appFont(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if store.busy.contains(repo.id) { ProgressView().controlSize(.small) }
                if repo.isPinned == true { Image(systemName: "pin.fill").appFont(.caption).foregroundStyle(.secondary) }
            }
            Label(status?.branch ?? "–", systemImage: "arrow.triangle.branch")
                .appFont(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: Spacing.xs) {
                if let s = status {
                    if let op = s.operation { StatusPill(text: op.title, symbol: "exclamationmark.triangle.fill", tint: Theme.conflict) }
                    if s.ahead > 0 { StatusPill(text: "↑\(s.ahead)") }
                    if s.behind > 0 { StatusPill(text: "↓\(s.behind)") }
                    if s.changedFiles > 0 { StatusPill(text: "\(s.changedFiles) changed", tint: Theme.modified) }
                    if s.upstream == nil { StatusPill(text: s.remote == nil ? "no remote" : "unpublished", symbol: "icloud.slash") }
                    if s.changedFiles == 0 && s.ahead == 0 && s.behind == 0 && s.upstream != nil {
                        StatusPill(text: "up to date", symbol: "checkmark", tint: Theme.added)
                    }
                } else {
                    StatusPill(text: "unavailable", symbol: "questionmark.folder", tint: Theme.deleted)
                }
            }
            HStack(alignment: .bottom) {
                Sparkline(values: sparkline).frame(height: 22)
                Spacer(minLength: Spacing.s)
                Text(status?.lastFetched.map { "fetched \(RelativeTime.string($0))" } ?? "never fetched")
                    .appFont(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(Spacing.m)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.l))
        .contentShape(Rectangle())
        .help(repo.path)
        .accessibilityElement(children: .combine)
    }
}

/// Tiny bar chart (commits per day).
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 1)
                    .fill(v == 0 ? Theme.separator : Theme.accent.opacity(0.75))
                    .frame(width: 5, height: max(2, 22 * CGFloat(v) / CGFloat(peak)))
            }
        }
        .help("Commits per day, last 14 days")
        .accessibilityHidden(true)
    }
}
