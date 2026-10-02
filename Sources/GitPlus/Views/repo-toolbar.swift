import AppKit
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
                ReviewsToolbarButton(repo: repo, provider: provider)
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

/// One sync button that does the obvious next step (Fetch → Pull → Push → Publish, like GitHub Desktop),
/// with every other sync action in its menu.
struct SyncToolbarButton: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let status: RepoStatus?

    var body: some View {
        let busy = store.busy.contains(repo.id)
        let suggestion = SyncSuggestion(status)
        Menu {
            Button("Fetch") { Task { await store.fetch([repo.id]) } }
            Section("Pull") {
                ForEach(PullMode.allCases, id: \.self) { mode in
                    Button("Pull (\(mode.title))") { Task { await store.pull([repo.id], mode: mode) } }
                }
            }
            Section("Push") {
                Button(status?.upstream == nil ? "Publish Branch" : "Push") { Task { await store.push(repo.id) } }
                    .disabled(status?.remote == nil)
                Button("Force Push (with Lease)…") { ForcePushConfirmation.run(store, repo.id) }
                    .disabled(status?.upstream == nil)
            }
            Divider()
            Button("Remotes…") { RepoActions.post(.showRemotes) }
        } label: {
            if busy {
                Label { Text("Syncing…") } icon: { ProgressView().controlSize(.small) }.labelStyle(.titleAndIcon)
            } else {
                Label(suggestion.title, systemImage: suggestion.symbol).labelStyle(.titleAndIcon)
            }
        } primaryAction: {
            primary(suggestion)
        }
        .disabled(busy)
        .help(help(suggestion))
    }

    private func primary(_ suggestion: SyncSuggestion) {
        switch suggestion {
        case .noRemote: RepoActions.post(.showRemotes)
        case .publish, .push: Task { await store.push(repo.id) }
        case .pull: Task { await store.pull([repo.id]) }
        case .fetch: Task { await store.fetch([repo.id]) }
        case .diverged(let ahead, let behind): DivergedPrompt.run(store, repo.id, ahead: ahead, behind: behind)
        }
    }

    private func help(_ suggestion: SyncSuggestion) -> String {
        let fetched = status?.lastFetched.map { "Last fetched \(RelativeTime.string($0))" } ?? "Never fetched"
        switch suggestion {
        case .diverged: return "Your branch and its upstream have diverged — choose how to sync. \(fetched)"
        case .noRemote: return "This repository has no remote. Click to add one."
        default: return fetched
        }
    }
}

/// Asks how to sync a branch that diverged from its upstream.
@MainActor
enum DivergedPrompt {
    static func run(_ store: WorkspaceStore, _ id: UUID, ahead: Int, behind: Int) {
        let branch = store.statuses[id]?.branch ?? "Your branch"
        let alert = NSAlert()
        alert.messageText = "\(branch) has diverged"
        alert.informativeText = "You have \(ahead) commit\(ahead == 1 ? "" : "s") the remote doesn't have, and the remote has \(behind) you don't.\n\n"
            + "Rebase replays your commits on top of the remote ones (linear history). Merge creates a merge commit. "
            + "Force push replaces the remote branch — only use it when you rewrote history on purpose (e.g. after amending)."
        alert.addButton(withTitle: "Pull with Rebase")
        alert.addButton(withTitle: "Pull with Merge")
        alert.addButton(withTitle: "Force Push…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await store.pull([id], mode: .rebase) }
        case .alertSecondButtonReturn: Task { await store.pull([id], mode: .merge) }
        case .alertThirdButtonReturn: ForcePushConfirmation.run(store, id)
        default: break
        }
    }
}

struct ReviewsToolbarButton: View {
    let repo: RepoEntry
    let provider: GitProvider
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: { Label(provider.reviewNoun, systemImage: "arrow.triangle.pull") }
            .help("\(provider.reviewNoun) via \(provider.cliName ?? "")")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PullRequestsView(repo: repo, provider: provider) { isPresented = false }.frame(width: 860, height: 460)
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
