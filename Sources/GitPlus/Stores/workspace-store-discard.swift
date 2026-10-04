import Foundation

/// Discards that can be undone: the affected paths are backed up first and restored by the toast's Undo.
extension WorkspaceStore {
    func discard(_ files: [ChangedFile], in repoID: UUID) {
        let box = SnapshotBox()
        let success = files.count == 1 ? "Discarded \(files[0].path)" : "Discarded \(files.count) files"
        Task {
            await perform(repoID, "discard", success: success, undo: { git in
                if let backup = box.value { try await git.restore(backup) }
            }) { git in
                box.value = try await git.discardWithBackup(files)
            }
        }
    }

    /// Reverse-applies a line-selection patch to the worktree, keeping the file's previous content for Undo.
    func discardLines(_ count: Int, path: String, patch: String, in repoID: UUID) {
        let box = SnapshotBox()
        Task {
            await perform(repoID, "discard lines", success: "Discarded \(count) line\(count == 1 ? "" : "s")", undo: { git in
                if let backup = box.value { try await git.restore(backup) }
            }) { git in
                box.value = try await git.snapshot([path])
                try await git.apply(patch: patch, cached: false, reverse: true)
            }
        }
    }
}
