import SwiftUI

/// Left pane "Stashes" tab.
struct StashListView: View {
    let stashes: [StashEntry]
    @Binding var selection: StashEntry.ID?

    var body: some View {
        List(stashes, selection: $selection) { entry in
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text("\(entry.ref) • \(RelativeTime.string(entry.date))").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .listRowSeparator(.visible)
        }
        .listStyle(.plain)
        .overlay {
            if stashes.isEmpty {
                ContentUnavailableView("No stashes", systemImage: "tray",
                                       description: Text("Use “Stash all changes” in the Changes tab to set work aside."))
            }
        }
    }
}

/// Main area for a stash: actions bar + its diff.
struct StashDetailView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let entry: StashEntry
    @State private var confirmDrop = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
                Text(entry.ref).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { run("apply stash", "Stash applied") { try await $0.applyStash(entry, pop: false) } }
                    .help("Apply and keep the stash")
                Button("Pop") { run("pop stash", "Stash applied and removed") { try await $0.applyStash(entry, pop: true) } }
                    .buttonStyle(.glassProminent)
                    .help("Apply and remove the stash")
                Button("Drop…", role: .destructive) { confirmDrop = true }
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Rectangle().fill(Theme.separator).frame(height: 1)
            CommitDetailView(repoURL: repo.url, target: GitService.stashTarget(entry))
        }
        .confirmationDialog("Drop \(entry.ref)?", isPresented: $confirmDrop) {
            Button("Drop Stash", role: .destructive) { run("drop stash", "Stash dropped") { try await $0.dropStash(entry) } }
        } message: {
            Text("The stashed changes will be permanently deleted.")
        }
    }

    private func run(_ label: String, _ success: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, op) }
    }
}

/// Yellow banner while a merge / rebase / cherry-pick / revert is waiting.
struct OperationBannerView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let operation: GitOperation
    let conflicts: Int
    @State private var confirmAbort = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: conflicts > 0 ? "exclamationmark.triangle.fill" : "arrow.triangle.merge")
                .foregroundStyle(Theme.bannerBorder)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(operation.title) in progress").font(.system(size: 13, weight: .semibold))
                Text(conflicts > 0
                     ? "\(conflicts) conflicted file\(conflicts == 1 ? "" : "s"). Resolve in the Changes tab (Use Ours / Use Theirs / Mark as Resolved), then continue."
                     : "All conflicts resolved. Continue to finish the \(operation.title.lowercased()).")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if operation == .rebase {
                Button("Skip Commit") { run("skip") { try await $0.skipRebaseCommit() } }
            }
            Button("Abort…", role: .destructive) { confirmAbort = true }
            Button("Continue") { run("continue \(operation.rawValue)", "\(operation.title) completed") { try await $0.continueOperation(operation) } }
                .buttonStyle(.glassProminent)
                .disabled(conflicts > 0)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular.tint(Theme.bannerBorder.opacity(0.35)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .confirmationDialog("Abort \(operation.title.lowercased())?", isPresented: $confirmAbort) {
            Button("Abort \(operation.title)", role: .destructive) {
                run("abort", "\(operation.title) aborted") { try await $0.abortOperation(operation) }
            }
        } message: {
            Text("Your branch returns to the state before the \(operation.title.lowercased()) started.")
        }
    }

    private func run(_ label: String, _ success: String? = nil, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, op) }
    }
}
