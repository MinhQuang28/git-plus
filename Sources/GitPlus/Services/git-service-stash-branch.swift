import Foundation

/// Stash, branch management, merge/rebase and in-progress operations.
extension GitService {
    // MARK: Stash

    func stashes() async throws -> [StashEntry] {
        let out = try await git(["stash", "list", "--format=%H%x1f%gd%x1f%gs%x1f%aI%x1e"])
        let iso = ISO8601DateFormatter()
        return out.split(separator: "\u{1e}").compactMap { record in
            let f = record.trimmingCharacters(in: .newlines).split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { return nil }
            return StashEntry(hash: f[0], ref: f[1], message: f[2], date: iso.date(from: f[3]) ?? .distantPast)
        }
    }

    /// `paths` empty → stash everything.
    func stash(message: String, includeUntracked: Bool, paths: [String] = []) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if !message.isEmpty { args += ["-m", message] }
        if !paths.isEmpty { args += ["--"] + paths }
        _ = try await git(args)
    }

    func applyStash(_ entry: StashEntry, pop: Bool) async throws {
        _ = try await git(["stash", pop ? "pop" : "apply", "--index", entry.ref])
    }

    func dropStash(_ entry: StashEntry) async throws { _ = try await git(["stash", "drop", entry.ref]) }

    /// Diff target for a stash: its base commit vs the stashed tree.
    static func stashTarget(_ entry: StashEntry) -> DiffTarget {
        DiffTarget(base: "\(entry.hash)^1", head: entry.hash, title: entry.message)
    }

    // MARK: Branches

    func renameBranch(_ old: String, to new: String) async throws { _ = try await git(["branch", "-m", old, new]) }

    /// `force` deletes even when not merged.
    func deleteBranch(_ name: String, force: Bool) async throws { _ = try await git(["branch", force ? "-D" : "-d", name]) }

    /// `origin/feature` → `git push origin --delete feature`.
    func deleteRemoteBranch(_ remoteBranch: String) async throws {
        let parts = remoteBranch.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        _ = try await git(["push", parts[0], "--delete", parts[1]])
    }

    func merge(_ branch: String) async throws { _ = try await git(["merge", "--no-edit", branch]) }
    /// Stages the combined changes of `branch` without committing (`merge --squash`).
    func mergeSquash(_ branch: String) async throws { _ = try await git(["merge", "--squash", branch]) }
    func rebase(onto branch: String) async throws { _ = try await git(["-c", "core.editor=true", "rebase", branch]) }

    // MARK: In-progress operations

    func inProgressOperation() async -> GitOperation? {
        guard let dir = try? await git(["rev-parse", "--absolute-git-dir"]).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Self.operation(inGitDir: dir)
    }

    static func operation(inGitDir dir: String) -> GitOperation? {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: (dir as NSString).appendingPathComponent(name)) }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }

    /// `core.editor=true` accepts the prepared commit message without opening an editor.
    func continueOperation(_ op: GitOperation) async throws {
        _ = try await git(["-c", "core.editor=true", op.rawValue, "--continue"])
    }

    func abortOperation(_ op: GitOperation) async throws { _ = try await git([op.rawValue, "--abort"]) }
    func skipRebaseCommit() async throws { _ = try await git(["-c", "core.editor=true", "rebase", "--skip"]) }
}
