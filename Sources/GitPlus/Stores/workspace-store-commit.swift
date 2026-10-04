import Foundation

/// Committing from the stored draft, so the commit box, the menu bar and shortcuts share one path.
extension WorkspaceStore {
    /// What the commit box shows: the typed draft, or the Settings → Commit defaults.
    func draft(for id: UUID) -> CommitDraft {
        commitDrafts[id] ?? CommitDraft(summary: UserDefaults.standard.string(forKey: CommitDefaults.summaryKey) ?? "",
                                        details: UserDefaults.standard.string(forKey: CommitDefaults.descriptionKey) ?? "")
    }

    /// Other running operations don't block: the commit queues behind them.
    func canCommit(_ id: UUID) -> Bool {
        let draft = draft(for: id)
        return !draft.summary.trimmingCharacters(in: .whitespaces).isEmpty
            && (draft.amend || !(trees[id]?.isEmpty ?? true))
            && busyLabels[id] != "commit"
            && (statuses[id]?.conflicts ?? 0) == 0
    }

    /// Nothing staged (and not amending) → stages everything first, like GitHub Desktop.
    func commit(_ id: UUID, push: Bool) {
        guard canCommit(id) else { return }
        let draft = draft(for: id)
        let summary = draft.summary.trimmingCharacters(in: .whitespaces)
        let details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAmend = draft.amend
        let stageFirst = (trees[id]?.staged.isEmpty ?? true) && !isAmend
        let needsUpstream = statuses[id]?.upstream == nil
        let branch = statuses[id]?.branch ?? "HEAD"
        // Explicit `if` instead of a ternary: the closure-in-ternary form crashes the type checker.
        var undo: (@Sendable (GitService) async throws -> Void)? = nil
        if !isAmend { undo = { git in try await git.undoLastCommit() } }
        Task {
            let ok = await perform(id, "commit", success: push ? nil : isAmend ? "Amended last commit" : "Committed to \(branch)",
                                   undo: undo) {
                if stageFirst { try await $0.stageAll() }
                try await $0.commit(summary: summary, description: details, amend: isAmend)
            }
            guard ok else { return }
            commitDrafts[id] = nil
            if push { await self.push(id, force: isAmend && !needsUpstream) }
        }
    }
}
