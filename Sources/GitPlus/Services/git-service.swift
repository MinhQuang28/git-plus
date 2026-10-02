import Foundation

/// Thin wrapper over the system `git` CLI. All methods are read-only except fetch/pull.
struct GitService: Sendable {
    let repo: URL

    static func isRepository(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    // MARK: Status

    func status() async throws -> RepoStatus {
        let out = try await git(["status", "--porcelain=v2", "--branch"])
        var status = GitParsers.status(out)
        status.remote = await remote()
        status.lastFetched = await lastFetched()
        status.operation = await inProgressOperation()
        return status
    }

    private func lastFetched() async -> Date? {
        guard let rel = try? await git(["rev-parse", "--git-path", "FETCH_HEAD"]) else { return nil }
        let path = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : repo.appendingPathComponent(path)
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Remote of `origin`, falling back to the first configured remote.
    func remote() async -> RemoteInfo? {
        if let url = try? await git(["remote", "get-url", "origin"]), let info = RemoteInfo.parse(url) {
            return info
        }
        guard let first = (try? await git(["remote"]))?.split(separator: "\n").first,
              let url = try? await git(["remote", "get-url", String(first)]) else { return nil }
        return RemoteInfo.parse(url)
    }

    /// Local and remote branches, most recently committed first.
    func branches() async throws -> BranchList {
        let out = try await git(["for-each-ref", "--sort=-committerdate", "--format=%(refname)%09%(HEAD)", "refs/heads", "refs/remotes"])
        var list = BranchList()
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            let ref = String(cols[0])
            if ref.hasPrefix("refs/heads/") {
                let name = String(ref.dropFirst("refs/heads/".count))
                list.local.append(name)
                if cols.count > 1, cols[1] == "*" { list.current = name }
            } else if ref.hasPrefix("refs/remotes/"), !ref.hasSuffix("/HEAD") {
                list.remote.append(String(ref.dropFirst("refs/remotes/".count)))
            }
        }
        return list
    }

    /// Switches to a local branch, or creates a tracking branch for `remote/name`.
    func switchBranch(_ name: String, isRemote: Bool = false) async throws {
        if isRemote {
            _ = try await git(["switch", "--track", name])
        } else {
            _ = try await git(["switch", name])
        }
    }

    func createBranch(_ name: String) async throws { _ = try await git(["switch", "-c", name]) }

    // MARK: History

    /// `ref == nil` → current HEAD. `allRefs` → every branch (like `git log --all`).
    func log(ref: String? = nil, allRefs: Bool = false, limit: Int = 300, search: String? = nil) async throws -> [Commit] {
        var args = ["log", "--format=\(GitParsers.logFormat)", "--date-order", "-n", String(limit)]
        if let search, !search.isEmpty { args += ["-i", "--grep=\(search)"] }
        if allRefs { args.append("--all") } else if let ref { args.append(ref) }
        args.append("--")
        do {
            return GitParsers.commits(try await git(args))
        } catch let error as CommandError where error.stderr.contains("does not have any commits") {
            return []
        }
    }

    // MARK: Diff

    func changedFiles(_ target: DiffTarget) async throws -> [ChangedFile] {
        let range = [target.base, target.head]
        async let names = git(["diff", "--name-status", "-M", "--no-color"] + range + ["--"])
        async let stats = git(["diff", "--numstat", "-M", "--no-color"] + range + ["--"])
        return GitParsers.changedFiles(nameStatus: try await names, numstat: try await stats)
    }

    func diff(_ target: DiffTarget, file: ChangedFile, context: Int = 3) async throws -> String {
        var paths = [file.path]
        if let old = file.oldPath { paths.insert(old, at: 0) }
        return try await git(["diff", "-M", "--no-color", "--no-ext-diff", "-U\(context)", target.base, target.head, "--"] + paths)
    }

    func commitMessage(_ hash: String) async throws -> String {
        try await git(["show", "-s", "--format=%B", hash])
    }

    // MARK: Network

    func fetch() async throws { _ = try await git(["fetch", "--all", "--prune"]) }
    func pull() async throws { _ = try await git(["pull", "--ff-only"]) }
    /// Pushes the current branch; sets upstream on first push.
    func push(setUpstream: Bool) async throws {
        _ = try await git(setUpstream ? ["push", "-u", "origin", "HEAD"] : ["push"])
    }
}
