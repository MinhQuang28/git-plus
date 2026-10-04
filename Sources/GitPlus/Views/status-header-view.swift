import SwiftUI

/// Compact banner under the repository switcher, shown only when the branch needs attention
/// (unpublished, diverged, conflicts): one line of state + the next step. Branch name and change
/// count already live in the toolbar and the Changes header, so they aren't repeated here.
struct RepoStatusHeader: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let status: RepoStatus?

    var body: some View {
        let suggestion = SyncSuggestion(status)
        let conflicts = status?.conflicts ?? 0
        if conflicts > 0 {
            banner(symbol: "exclamationmark.triangle.fill", tint: Theme.conflict,
                   text: "\(conflicts) conflicted file\(conflicts == 1 ? "" : "s")") {
                Button("Resolve…") { RepoActions.post(.showConflicts) }.buttonStyle(.glassProminent)
            }
        } else if case .diverged(let ahead, let behind) = suggestion {
            banner(symbol: "arrow.up.arrow.down", tint: Theme.modified, text: "Diverged ↑\(ahead) ↓\(behind)",
                   help: "\(ahead) local and \(behind) remote commits. Rebase or merge to combine them.") {
                Button("Rebase") { Task { await store.pull([repo.id], mode: .rebase) } }.buttonStyle(.glassProminent)
                Menu {
                    Button("Merge") { Task { await store.pull([repo.id], mode: .merge) } }
                    Button("Force Push (with Lease)…") { ForcePushConfirmation.run(store, repo.id) }
                } label: {
                    Label("More ways to combine", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .menuStyle(.button).buttonStyle(.glass).menuIndicator(.hidden).fixedSize()
            }
        } else if case .publish = suggestion {
            banner(symbol: "icloud.slash", tint: .secondary, text: "Not published yet",
                   help: "This branch only exists on your Mac.") {
                Button("Publish") { Task { await store.push(repo.id) } }.buttonStyle(.glassProminent)
            }
        }
    }

    private func banner<Actions: View>(symbol: String, tint: Color, text: String, help: String? = nil,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol).foregroundStyle(tint).appFont(.callout)
            Text(text).appFont(.callout, weight: .medium).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Spacing.xs)
            HStack(spacing: Spacing.xs) { actions() }
                .controlSize(.small)
                .disabled(store.busy.contains(repo.id))
        }
        .padding(.leading, Spacing.m).padding(.trailing, Spacing.s).padding(.vertical, Spacing.xs + 2)
        .background(RoundedRectangle(cornerRadius: Radius.s).fill(Theme.headerBackground))
        .help(help ?? text)
        .padding(.horizontal, Spacing.s).padding(.top, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(help.map { "\(text). \($0)" } ?? text)
    }
}
