import Foundation

/// Thin wrapper over the system `git` CLI. All methods are read-only except fetch/pull.
struct GitService: Sendable {
    let repo: URL

    private func git(_ args: [String]) async throws -> String {
        try await ProcessRunner.run("git", args, in: repo)
    }

    static func isRepository(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    // MARK: Status

    func status() async throws -> RepoStatus {
        let out = try await git(["status", "--porcelain=v2", "--branch"])
        var status = GitParsers.status(out)
        status.remote = await remote()
        return status
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

    func branches() async throws -> [String] {
        let out = try await git(["for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/heads", "refs/remotes"])
        return out.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }
    }

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
}
