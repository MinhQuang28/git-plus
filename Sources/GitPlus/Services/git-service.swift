import Foundation

/// Thin wrapper over the system `git` CLI. All methods are read-only except fetch/pull.
struct GitService: Sendable {
    let repo: URL

    static func isRepository(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    // MARK: Status

    func status() async throws -> RepoStatus { try await snapshot(includeTree: false).status }

    /// Repo summary and (optionally) the full Changes list from a single `git status`.
    /// `includeTree` lists every untracked file (needed for the Changes tab, slower on huge trees).
    func snapshot(includeTree: Bool) async throws -> (status: RepoStatus, tree: WorkingTree) {
        async let porcelain = git(["status", "--porcelain=v2", "-z", "--branch"] + (includeTree ? ["--untracked-files=all"] : []))
        async let meta = RepoMetaCache.meta(for: self)
        var (status, tree) = GitParsers.snapshot(try await porcelain)
        let m = await meta
        if let dir = m.gitDir {
            status.operation = Self.operation(inGitDir: dir)
            status.lastFetched = m.fetchHead.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
        }
        status.remote = Self.preferredRemote(m.remotes).flatMap { RemoteInfo.parse($0.url) }
        return (status, tree)
    }

    /// `remote.<name>.url` for every configured remote, in config order.
    func remoteURLs() async -> [(name: String, url: String)] {
        let out = (try? await ProcessRunner.run("git", ["config", "--get-regexp", "^remote\\..*\\.url$"], in: repo, okCodes: [0, 1])) ?? ""
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("remote."), parts[0].hasSuffix(".url") else { return nil }
            return (name: String(parts[0].dropFirst("remote.".count).dropLast(".url".count)), url: parts[1])
        }
    }

    /// `origin` when it exists, otherwise the first remote.
    static func preferredRemote(_ remotes: [(name: String, url: String)]) -> (name: String, url: String)? {
        remotes.first { $0.name == "origin" } ?? remotes.first
    }

    /// Remote of `origin`, falling back to the first configured remote.
    func remote() async -> RemoteInfo? {
        Self.preferredRemote(await remoteURLs()).flatMap { RemoteInfo.parse($0.url) }
    }

    /// Name of the remote used for publishing (`origin`, else the first one).
    func defaultRemoteName() async -> String? { Self.preferredRemote(await remoteURLs())?.name }

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
    /// `search` → message grep; `author` and `paths` narrow it down further. `skip` pages through history.
    func log(ref: String? = nil, allRefs: Bool = false, limit: Int = 300, skip: Int = 0, search: String? = nil,
             author: String? = nil, paths: [String] = [], follow: Bool = false) async throws -> [Commit] {
        var args = ["log", "--format=\(GitParsers.logFormat)", "--date-order", "-n", String(limit)]
        if skip > 0 { args.append("--skip=\(skip)") }
        if let search, !search.isEmpty { args += ["-i", "--fixed-strings", "--grep=\(search)"] }
        if let author, !author.isEmpty { args += ["-i", "--author=\(author)"] }
        if follow { args.append("--follow") }
        if allRefs { args.append("--all") } else if let ref { args.append(ref) }
        args.append("--")
        args += paths
        do {
            return GitParsers.commits(try await git(args))
        } catch let error as CommandError where error.stderr.contains("does not have any commits") || error.stderr.contains("unknown revision") {
            return []
        }
    }

    /// Commits matching a history search. Plain text matches the message *or* the author
    /// (git ANDs `--grep` with `--author`, so the two are queried separately and merged).
    func search(_ query: HistoryQuery, ref: String? = nil, allRefs: Bool = false, limit: Int = 300) async throws -> [Commit] {
        if query.text.isEmpty {
            return try await log(ref: ref, allRefs: allRefs, limit: limit, author: query.author, paths: query.paths)
        }
        async let byMessage = log(ref: ref, allRefs: allRefs, limit: limit, search: query.text, author: query.author, paths: query.paths)
        async let byAuthor = authorMatches(query, ref: ref, allRefs: allRefs, limit: limit)
        var seen = Set<String>()
        var merged = (try await byMessage) + (try await byAuthor)
        if query.looksLikeHash, let hit = try? await git(["log", "-1", "--format=\(GitParsers.logFormat)", query.text, "--"]) {
            merged = GitParsers.commits(hit) + merged
        }
        return merged.filter { seen.insert($0.hash).inserted }.sorted { $0.date > $1.date }
    }

    private func authorMatches(_ query: HistoryQuery, ref: String?, allRefs: Bool, limit: Int) async throws -> [Commit] {
        guard query.author == nil else { return [] }
        return try await log(ref: ref, allRefs: allRefs, limit: limit, author: query.text, paths: query.paths)
    }

    // MARK: Diff

    func changedFiles(_ target: DiffTarget) async throws -> [ChangedFile] {
        let range = [target.base, target.head]
        // One process: rename detection (the expensive part) runs once for both status and line counts.
        return GitParsers.changedFiles(rawNumstat: try await git(["diff", "--raw", "--numstat", "-z", "-M", "--no-color"] + range + ["--"]))
    }

    func diff(_ target: DiffTarget, file: ChangedFile, context: Int = 3, ignoreWhitespace: Bool = false) async throws -> String {
        var paths = [file.path]
        if let old = file.oldPath { paths.insert(old, at: 0) }
        let ws = ignoreWhitespace ? ["-w"] : []
        return try await git(["diff", "-M", "--no-color", "--no-ext-diff", "-U\(context)"] + ws + [target.base, target.head, "--"] + paths)
    }

    func commitMessage(_ hash: String) async throws -> String {
        try await git(["show", "-s", "--format=%B", hash])
    }

    // MARK: Network

    func fetch() async throws { _ = try await git(["fetch", "--all", "--prune"]) }
    func pull(_ mode: PullMode = .fastForward) async throws { _ = try await git(["-c", "core.editor=true", "pull"] + mode.args) }

    /// Pushes the current branch; sets upstream on first push. `force` uses `--force-with-lease`,
    /// which refuses to overwrite remote commits you haven't fetched.
    func push(setUpstream: Bool, force: Bool = false) async throws {
        var args = ["push"]
        if force { args.append("--force-with-lease") }
        if setUpstream {
            args += ["-u", await defaultRemoteName() ?? "origin", "HEAD"]
        }
        _ = try await git(args)
    }
}
