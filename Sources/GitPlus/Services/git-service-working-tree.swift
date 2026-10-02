import Foundation

/// Working tree & index ("Changes" tab): list, diff, stage/unstage, discard, commit.
extension GitService {
    func workingTree() async throws -> WorkingTree {
        GitParsers.snapshot(try await git(["status", "--porcelain=v2", "-z", "--untracked-files=all"])).tree
    }

    var hasUncommittedChanges: Bool {
        get async { !((try? await workingTree())?.isEmpty ?? true) }
    }

    /// Staged → HEAD vs index; unstaged → index vs worktree; untracked → /dev/null vs file.
    func workingDiff(_ file: ChangedFile, context: Int = 3, ignoreWhitespace: Bool = false) async throws -> String {
        let common = ["--no-color", "--no-ext-diff", "-U\(context)"] + (ignoreWhitespace ? ["-w"] : [])
        switch (file.area, file.status) {
        case (.unstaged, "?"):
            // Exit code 1 means "differences found" for --no-index.
            return try await ProcessRunner.run("git", ["diff", "--no-index"] + common + ["--", "/dev/null", file.path],
                                               in: repo, okCodes: [0, 1])
        case (.conflicted, _):
            let text = (try? String(contentsOf: repo.appendingPathComponent(file.path), encoding: .utf8)) ?? ""
            return DiffParser.conflictDiff(text)
        case (.staged, _):
            return try await git(["diff", "--cached", "-M"] + common + ["--"] + file.pathspec)
        default:
            return try await git(["diff"] + common + ["--"] + file.pathspec)
        }
    }

    // MARK: Index

    func stage(_ files: [ChangedFile]) async throws {
        let paths = files.flatMap(\.pathspec)
        guard !paths.isEmpty else { return }
        _ = try await git(["add", "-A", "--"] + paths)
    }

    func unstage(_ files: [ChangedFile]) async throws {
        let paths = files.flatMap(\.pathspec)
        guard !paths.isEmpty else { return }
        if await headHash() == nil {
            _ = try await git(["rm", "--cached", "-r", "-q", "--"] + paths)   // unborn branch: nothing to restore from
        } else {
            _ = try await git(["restore", "--staged", "--"] + paths)
        }
    }

    func stageAll() async throws { _ = try await git(["add", "-A"]) }

    func unstageAll() async throws {
        if await headHash() == nil { _ = try await git(["rm", "--cached", "-r", "-q", "."]) } else { _ = try await git(["reset", "-q"]) }
    }

    /// Unstaged area: restore the index version (untracked files are deleted).
    /// Other areas: restore HEAD in both index and worktree.
    func discard(_ file: ChangedFile) async throws {
        if file.status == "?" {
            try FileManager.default.removeItem(at: repo.appendingPathComponent(file.path))
        } else if file.area == .unstaged {
            _ = try await git(["restore", "--worktree", "--"] + file.pathspec)
        } else {
            _ = try await git(["restore", "--staged", "--worktree", "--source=HEAD", "--"] + file.pathspec)
        }
    }

    /// Applies a patch built by `PatchBuilder` to the index (`cached`) or the worktree.
    func apply(patch: String, cached: Bool, reverse: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-\(UUID().uuidString).patch")
        try patch.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var args = ["apply", "--recount", "--unidiff-zero", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("-R") }
        _ = try await git(args + [url.path])
    }

    // MARK: Commit

    /// Commits the index. `amend` rewrites the last commit (message and/or content).
    func commit(summary: String, description: String, amend: Bool = false) async throws {
        var args = ["commit", "-m", summary]
        if !description.isEmpty { args += ["-m", description] }
        if amend { args.append("--amend") }
        _ = try await git(args)
    }

    func lastCommitMessage() async -> (summary: String, description: String) {
        let message = (try? await git(["log", "-1", "--format=%B"])) ?? ""
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts.first ?? ""), parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
    }

    // MARK: Conflicts

    /// Resolves a conflicted file with one side, then marks it resolved.
    func resolve(_ file: ChangedFile, useOurs: Bool) async throws {
        try await resolve(file, side: useOurs ? .ours : .theirs)
    }

    func markResolved(_ file: ChangedFile) async throws {
        // A side that deleted the file leaves nothing to add; `add -A` records the deletion too.
        _ = try await git(["add", "-A", "--", file.path])
    }

    func git(_ args: [String]) async throws -> String {
        try await ProcessRunner.run("git", args, in: repo)
    }
}
