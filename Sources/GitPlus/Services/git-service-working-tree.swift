import Foundation

/// Working tree ("Changes" tab): list, diff and commit selected files.
extension GitService {
    func workingChanges() async throws -> [ChangedFile] {
        let out = try await ProcessRunner.run("git", ["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: repo)
        return GitParsers.workingChanges(out)
    }

    func workingDiff(_ file: ChangedFile, context: Int = 3) async throws -> String {
        if file.status == "?" {
            // Untracked: diff against /dev/null; exit code 1 means "differences found".
            return try await ProcessRunner.run(
                "git", ["diff", "--no-index", "--no-color", "-U\(context)", "--", "/dev/null", file.path],
                in: repo, okCodes: [0, 1])
        }
        var paths = [file.path]
        if let old = file.oldPath { paths.insert(old, at: 0) }
        let base = (try? await ProcessRunner.run("git", ["rev-parse", "--verify", "-q", "HEAD"], in: repo)) != nil
            ? "HEAD" : DiffTarget.emptyTree
        return try await ProcessRunner.run("git", ["diff", "--no-color", "--no-ext-diff", "-M", "-U\(context)", base, "--"] + paths, in: repo)
    }

    /// Commits exactly `files` (other staged changes are left staged but not committed).
    func commit(files: [ChangedFile], summary: String, description: String) async throws {
        let paths = files.flatMap { [$0.oldPath, $0.path].compactMap { $0 } }
        guard !paths.isEmpty else { return }
        _ = try await ProcessRunner.run("git", ["add", "-A", "--"] + paths, in: repo)
        var args = ["commit", "-m", summary]
        if !description.isEmpty { args += ["-m", description] }
        _ = try await ProcessRunner.run("git", args + ["--only", "--"] + paths, in: repo)
    }

    /// Discards local changes of one file (restores HEAD version, deletes if untracked).
    func discard(_ file: ChangedFile) async throws {
        if file.status == "?" {
            try FileManager.default.removeItem(at: repo.appendingPathComponent(file.path))
        } else {
            _ = try await ProcessRunner.run("git", ["restore", "--staged", "--worktree", "--source=HEAD", "--", file.path], in: repo)
        }
    }

    var hasUncommittedChanges: Bool {
        get async { !((try? await workingChanges()) ?? []).isEmpty }
    }
}

/// History context-menu actions (mirrors GitHub Desktop's commit menu).
extension GitService {
    /// Mixed reset: moves the branch to `hash`, keeping later changes in the working tree.
    func reset(to hash: String) async throws { _ = try await run(["reset", "--mixed", hash]) }
    func checkout(commit hash: String) async throws { _ = try await run(["switch", "--detach", hash]) }
    func createBranch(_ name: String, at hash: String) async throws { _ = try await run(["switch", "-c", name, hash]) }
    func createTag(_ name: String, at hash: String) async throws { _ = try await run(["tag", name, hash]) }

    func revert(_ commit: Commit) async throws {
        let mainline = commit.parents.count > 1 ? ["-m", "1"] : []
        _ = try await run(["revert", "--no-edit"] + mainline + [commit.hash])
    }

    /// Applies `hash` onto `branch`, then returns to the original branch.
    /// Requires a clean tree; aborts and restores the original branch on conflict.
    func cherryPick(_ hash: String, onto branch: String) async throws {
        guard await !hasUncommittedChanges else {
            throw CommandError(command: "cherry-pick", status: 1, stderr: "Commit or discard your changes before cherry-picking.")
        }
        let original = try await run(["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await run(["switch", branch])
        do {
            _ = try await run(["cherry-pick", hash])
        } catch {
            _ = try? await run(["cherry-pick", "--abort"])
            _ = try? await run(["switch", original])
            throw error
        }
        _ = try await run(["switch", original])
    }

    func headHash() async -> String? {
        (try? await run(["rev-parse", "--verify", "-q", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commits only in HEAD (ahead) and only in `branch` (behind).
    func aheadBehind(_ branch: String) async -> (ahead: Int, behind: Int) {
        let out = (try? await run(["rev-list", "--left-right", "--count", "HEAD...\(branch)"])) ?? ""
        let n = out.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        return n.count == 2 ? (n[0], n[1]) : (0, 0)
    }

    private func run(_ args: [String]) async throws -> String {
        try await ProcessRunner.run("git", args, in: repo)
    }
}
