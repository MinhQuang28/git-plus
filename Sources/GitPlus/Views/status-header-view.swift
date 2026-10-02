import SwiftUI

/// Card under the repository switcher: branch → upstream, sync / change state at a glance,
/// and a callout with the next step. Only shown when the branch needs attention (diverged, unpublished,
/// conflicts); the toolbar already covers the normal state and the operation banner covers merges/rebases.
struct RepoStatusHeader: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let status: RepoStatus?

    var body: some View {
        let suggestion = SyncSuggestion(status)
        if suggestion.needsAttention || (status?.conflicts ?? 0) > 0 { card(suggestion) }
    }

    private func card(_ suggestion: SyncSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                Text(status?.branch ?? "–").font(.rowTitle).lineLimit(1).truncationMode(.middle)
                if let upstream = status?.upstream {
                    Text("→ \(upstream)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            if let s = status {
                HStack(spacing: Spacing.xs) {
                    if s.ahead > 0 { StatusPill(text: "↑\(s.ahead)", tint: Theme.ahead) }
                    if s.behind > 0 { StatusPill(text: "↓\(s.behind)", tint: Theme.behind) }
                    if s.conflicts > 0 {
                        StatusPill(text: "\(s.conflicts) conflicted", symbol: "exclamationmark.triangle.fill", tint: Theme.conflict)
                    } else if s.changedFiles > 0 {
                        StatusPill(text: "\(s.changedFiles) changed", symbol: "pencil", tint: Theme.modified)
                    } else {
                        StatusPill(text: "clean", symbol: "checkmark", tint: Theme.added)
                    }
                    Spacer(minLength: 0)
                }
            }
            callout(suggestion)
        }
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.m).fill(Theme.headerBackground))
        .padding([.horizontal, .top], Spacing.s)
        .padding(.bottom, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func callout(_ suggestion: SyncSuggestion) -> some View {
        switch suggestion {
        case .diverged(let ahead, let behind):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Diverged: \(ahead) local and \(behind) remote commit\(behind == 1 ? "" : "s"). Choose how to combine them.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s) {
                    Button("Rebase") { Task { await store.pull([repo.id], mode: .rebase) } }.buttonStyle(.glassProminent)
                    Button("Merge") { Task { await store.pull([repo.id], mode: .merge) } }.buttonStyle(.glass)
                    Button("Force Push…") { ForcePushConfirmation.run(store, repo.id) }.buttonStyle(.glass)
                }
                .controlSize(.small)
                .disabled(store.busy.contains(repo.id))
            }
        case .publish:
            HStack(spacing: Spacing.s) {
                Text("This branch only exists on your Mac.").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Publish") { Task { await store.push(repo.id) } }
                    .buttonStyle(.glassProminent).controlSize(.small)
                    .disabled(store.busy.contains(repo.id))
            }
        default:
            EmptyView()
        }
    }
}
