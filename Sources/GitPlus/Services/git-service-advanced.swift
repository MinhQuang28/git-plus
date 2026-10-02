import Foundation

/// Tags, remotes, undo, bulk discard, interactive rebase, file history / blame, conflicts, clone / init.
extension GitService {
    // MARK: Tags

    func tags() async throws -> [TagInfo] {
        let format = "%(refname:short)%1f%(objectname:short)%1f%(creatordate:iso-strict)%1f%(subject)"
        let out = try await git(["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"])
        return GitParsers.tags(out)
    }

    func pushTag(_ name: String) async throws {
        _ = try await git(["push", await defaultRemoteName() ?? "origin", "refs/tags/\(name)"])
    }

    func pushAllTags() async throws { _ = try await git(["push", await defaultRemoteName() ?? "origin", "--tags"]) }
    func deleteTag(_ name: String) async throws { _ = try await git(["tag", "-d", name]) }
    func deleteRemoteTag(_ name: String) async throws {
        _ = try await git(["push", await defaultRemoteName() ?? "origin", "--delete", "refs/tags/\(name)"])
    }

    // MARK: Remotes

    func remotes() async throws -> [RemoteEntry] { GitParsers.remotes(try await git(["remote", "-v"])) }
    func addRemote(_ name: String, url: String) async throws { _ = try await git(["remote", "add", name, url]) }
    func removeRemote(_ name: String) async throws { _ = try await git(["remote", "remove", name]) }
    func setRemoteURL(_ name: String, url: String) async throws { _ = try await git(["remote", "set-url", name, url]) }

    // MARK: Undo & discard

    /// Moves the last commit's changes back to the index (`reset --soft HEAD~1`).
    /// For the very first commit the branch becomes unborn again, keeping the files staged.
    func undoLastCommit() async throws {
        if (try? await git(["rev-parse", "--verify", "-q", "HEAD~1"])) != nil {
            _ = try await git(["reset", "--soft", "HEAD~1"])
        } else {
            _ = try await git(["update-ref", "-d", "HEAD"])
        }
    }

    func discard(_ files: [ChangedFile]) async throws {
        for file in files { try await discard(file) }
    }

    /// Discards every local change by moving it to a stash, so it can be restored with "Undo".
    func discardAll() async throws {
        _ = try await git(["stash", "push", "--include-untracked", "-m", "Discarded by Git Plus"])
    }

    /// Restores what `discardAll()` put aside.
    func undoDiscardAll() async throws { _ = try await git(["stash", "pop", "--index", "stash@{0}"]) }

    /// The subset of `paths` (absolute or repo-relative) that `.gitignore` rules ignore.
    func ignoredPaths(_ paths: [String]) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        // Exit status 1 means "none of them is ignored".
        let out = (try? await ProcessRunner.run("git", ["check-ignore", "--"] + paths.prefix(200), in: repo, okCodes: [0, 1])) ?? ""
        return Set(out.split(separator: "\n").map(String.init))
    }

    /// Appends a pattern to the repository's root `.gitignore`.
    func addToGitignore(_ pattern: String) throws {
        let url = repo.appendingPathComponent(".gitignore")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let existing = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !existing.contains(pattern) else { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += pattern + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Interactive rebase

    /// Rewrites the commits after `base` (nil → from the root) following `steps` (oldest first).
    /// The todo list is written by a non-interactive sequence editor; reworded messages are
    /// applied with `exec git commit --amend -F <file>` right after the picked commit.
    func rebaseInteractive(base: String?, steps: [RebaseStep]) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-rebase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var todo: [String] = []
        for (i, step) in steps.enumerated() {
            switch step.action {
            case .reword:
                let messageFile = dir.appendingPathComponent("message-\(i).txt")
                try step.message.write(to: messageFile, atomically: true, encoding: .utf8)
                todo.append("pick \(step.commit.hash)")
                todo.append("exec git commit --amend --allow-empty --quiet --cleanup=strip -F \(Self.shellQuote(messageFile.path))")
            default:
                todo.append("\(step.action.rawValue) \(step.commit.hash)")
            }
        }
        let todoFile = dir.appendingPathComponent("todo.txt")
        try (todo.joined(separator: "\n") + "\n").write(to: todoFile, atomically: true, encoding: .utf8)

        let editor = "cp \(Self.shellQuote(todoFile.path))"
        _ = try await git(["-c", "sequence.editor=\(editor)", "-c", "core.editor=true",
                           "rebase", "-i", "--no-autosquash"] + (base.map { [$0] } ?? ["--root"]))
        // Kept when the rebase stops on a conflict: later `exec` lines still need the message files.
        try? FileManager.default.removeItem(at: dir)
    }

    /// Changes the message of any commit on the current branch (amend for HEAD, rebase otherwise).
    func reword(_ commit: Commit, message: String) async throws {
        if await headHash() == commit.hash {
            _ = try await git(["commit", "--amend", "--allow-empty", "--only", "--cleanup=strip", "-m", message])
            return
        }
        let base = commit.parents.first
        let range = base.map { "\($0)..HEAD" } ?? "HEAD"
        let commits = try await log(ref: range, limit: 10_000).reversed()
        guard !commits.contains(where: { $0.parents.count > 1 }) else {
            throw CommandError(command: "reword", status: 1, stderr: "This commit is followed by merge commits; rewording it would flatten them.")
        }
        let steps = commits.map { RebaseStep(commit: $0, action: $0.hash == commit.hash ? .reword : .pick, message: message) }
        try await rebaseInteractive(base: base, steps: Array(steps))
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: File history & blame

    /// Commits touching `path` (following renames), each with the file's path at that commit.
    func fileHistory(_ path: String, limit: Int = 500) async throws -> [FileRevision] {
        let format = "%x1e" + GitParsers.logFormat.replacingOccurrences(of: "%x1e", with: "")
        let out = try await git(["log", "--follow", "-M", "--date-order", "-n", String(limit), "--format=\(format)", "--name-status", "--", path])
        return GitParsers.fileHistory(out)
    }

    func blame(_ path: String, at revision: String? = nil) async throws -> [BlameLine] {
        GitParsers.blame(try await git(["blame", "--porcelain"] + (revision.map { [$0] } ?? []) + ["--", path]))
    }

    /// File contents at a revision (`HEAD:path`, `:path` for the index); nil when it doesn't exist there.
    func blob(_ spec: String) async -> Data? {
        try? await ProcessRunner.runData("git", ["show", spec], in: repo)
    }

    // MARK: Conflicts

    /// Branch / commit names for both sides of the operation in progress, as GitHub Desktop shows them.
    /// During a rebase "ours" is the branch being rebased onto and "theirs" is your commit being replayed.
    func conflictSides(_ op: GitOperation) async -> (ours: String, theirs: String) {
        let dir = ((try? await git(["rev-parse", "--absolute-git-dir"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        func read(_ name: String) -> String? {
            (try? String(contentsOfFile: (dir as NSString).appendingPathComponent(name), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let current = ((try? await git(["rev-parse", "--abbrev-ref", "HEAD"])) ?? "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        switch op {
        case .merge:
            let mergeHead = read("MERGE_HEAD")?.split(separator: "\n").first.map(String.init)
            let incoming = await name(of: mergeHead)
            return (current, Self.mergedBranch(fromMessage: read("MERGE_MSG")) ?? incoming ?? "incoming")
        case .rebase:
            let folder = FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("rebase-merge")) ? "rebase-merge" : "rebase-apply"
            let headName = read("\(folder)/head-name").map { $0.replacingOccurrences(of: "refs/heads/", with: "") } ?? "your branch"
            let ontoHash = read("\(folder)/onto")
            let onto = await name(of: ontoHash) ?? "upstream"
            return (onto, headName)
        case .cherryPick:
            let picked = await name(of: read("CHERRY_PICK_HEAD"))
            return (current, picked ?? "cherry-picked commit")
        case .revert:
            let reverted = await name(of: read("REVERT_HEAD"))
            return (current, "revert of \(reverted ?? "commit")")
        }
    }

    /// `Merge branch 'feature' into main` → `feature`.
    static func mergedBranch(fromMessage message: String?) -> String? {
        guard let first = message?.split(separator: "\n").first else { return nil }
        for prefix in ["Merge branch '", "Merge remote-tracking branch '"] where first.hasPrefix(prefix) {
            let rest = first.dropFirst(prefix.count)
            if let end = rest.firstIndex(of: "'") { return String(rest[..<end]) }
        }
        return nil
    }

    /// Readable name for a commit hash: a branch name when one points at it, else the short hash.
    private func name(of hash: String?) async -> String? {
        guard let hash, !hash.isEmpty else { return nil }
        if let n = try? await git(["name-rev", "--name-only", "--no-undefined", "--refs=refs/heads/*", "--refs=refs/remotes/*", hash]) {
            let trimmed = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains("~"), !trimmed.contains("^") {
                return trimmed.replacingOccurrences(of: "remotes/", with: "")
            }
        }
        return String(hash.prefix(7))
    }

    /// Number of `<<<<<<<` blocks left in a conflicted file (0 = markers resolved).
    func conflictMarkerCount(_ file: ChangedFile) -> Int {
        guard let text = try? String(contentsOf: repo.appendingPathComponent(file.path), encoding: .utf8) else { return 0 }
        return ConflictResolver.blocks(ConflictResolver.parse(text)).count
    }

    /// Resolves a conflicted file with one side's version. If that side deleted the file, the file is removed.
    func resolve(_ file: ChangedFile, side: ConflictSide) async throws {
        if file.deletedSide == side || file.conflictCode == "DD" {
            _ = try await git(["rm", "-q", "--", file.path])
        } else {
            _ = try await git(["checkout", side == .ours ? "--ours" : "--theirs", "--", file.path])
            try await markResolved(file)
        }
    }

    /// Writes a resolved file and stages it.
    func saveResolution(_ file: ChangedFile, text: String) async throws {
        try text.write(to: repo.appendingPathComponent(file.path), atomically: true, encoding: .utf8)
        try await markResolved(file)
    }

    /// Files that would conflict if `branch` were merged into HEAD (`git merge-tree`, git 2.38+).
    /// Returns nil when the preview is unavailable.
    func mergePreview(_ branch: String) async -> [String]? {
        do {
            let out = try await ProcessRunner.run("git", ["merge-tree", "--write-tree", "--name-only", "--no-messages", "HEAD", branch],
                                                  in: repo, okCodes: [0, 1])
            // First line is the tree id; the rest are conflicted paths.
            return out.split(separator: "\n").dropFirst().map(String.init).filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    // MARK: Clone & init

    static func clone(_ remote: String, into destination: URL) async throws {
        _ = try await ProcessRunner.run("git", ["clone", "--", remote, destination.path], in: destination.deletingLastPathComponent())
    }

    static func initRepository(at folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try await ProcessRunner.run("git", ["init", "-q"], in: folder)
    }

    /// `git@github.com:acme/api.git` → `api`.
    static func repositoryName(fromRemote remote: String) -> String? {
        if let info = RemoteInfo.parse(remote) { return info.name }
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let name = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init)
        return name?.isEmpty == false ? name : nil
    }
}
