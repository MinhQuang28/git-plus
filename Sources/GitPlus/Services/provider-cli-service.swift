import Foundation

/// Talks to GitHub / GitLab through the user's authenticated `gh` / `glab` CLIs,
/// so no tokens are stored by this app.
struct ProviderCLIService: Sendable {
    let repo: URL
    let provider: GitProvider

    enum ProviderError: LocalizedError {
        case unsupported, missingCLI(String)
        var errorDescription: String? {
            switch self {
            case .unsupported: "Remote is neither GitHub nor GitLab."
            case .missingCLI(let name): "`\(name)` was not found on PATH. Install it with `brew install \(name)` and run `\(name) auth login`."
            }
        }
    }

    /// state: "open" | "closed" | "merged" | "all"
    func pullRequests(state: String = "open", limit: Int = 50) async throws -> [PullRequestItem] {
        guard let cli = provider.cliName else { throw ProviderError.unsupported }
        guard await ProcessRunner.isAvailable(cli) else { throw ProviderError.missingCLI(cli) }

        switch provider {
        case .github:
            let fields = "number,title,author,headRefName,state,isDraft,url,updatedAt"
            let data = try await ProcessRunner.runData("gh", ["pr", "list", "--state", state, "--limit", String(limit), "--json", fields], in: repo)
            return try ProviderJSON.github(data)
        case .gitlab:
            var args = ["mr", "list", "--output", "json", "--per-page", String(limit)]
            switch state {
            case "closed": args.append("--closed")
            case "merged": args.append("--merged")
            case "all": args.append("--all")
            default: break
            }
            let data = try await ProcessRunner.runData("glab", args, in: repo)
            return try ProviderJSON.gitlab(data)
        case .other:
            throw ProviderError.unsupported
        }
    }

    /// Opens the provider's "new pull / merge request" page for the current branch (must be pushed).
    func createForCurrentBranch() async throws {
        guard let cli = provider.cliName else { throw ProviderError.unsupported }
        guard await ProcessRunner.isAvailable(cli) else { throw ProviderError.missingCLI(cli) }
        let args = provider == .github ? ["pr", "create", "--web"] : ["mr", "create", "--web", "--fill"]
        _ = try await ProcessRunner.run(cli, args, in: repo)
    }

    /// Checks out the branch of a pull / merge request locally.
    func checkout(_ number: Int) async throws {
        guard let cli = provider.cliName else { throw ProviderError.unsupported }
        guard await ProcessRunner.isAvailable(cli) else { throw ProviderError.missingCLI(cli) }
        _ = try await ProcessRunner.run(cli, [provider == .github ? "pr" : "mr", "checkout", String(number)], in: repo)
    }

    /// Returns `auth status` output of the CLI (stdout+stderr are both informative).
    static func authStatus(_ cli: String) async -> (ok: Bool, message: String) {
        guard await ProcessRunner.isAvailable(cli) else { return (false, "\(cli) is not installed") }
        do {
            let out = try await ProcessRunner.run(cli, ["auth", "status"])
            return (true, out)
        } catch let error as CommandError {
            return (false, error.stderr)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

/// JSON decoding for `gh pr list --json` and `glab mr list --output json`.
enum ProviderJSON {
    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private struct GHPull: Decodable {
        struct Author: Decodable { let login: String }
        let number: Int, title: String, author: Author?, headRefName: String
        let state: String, isDraft: Bool?, url: String, updatedAt: String?
    }

    private struct GLMerge: Decodable {
        struct Author: Decodable { let username: String }
        let iid: Int, title: String, author: Author?, source_branch: String
        let state: String, draft: Bool?, web_url: String, updated_at: String?
    }

    static func github(_ data: Data) throws -> [PullRequestItem] {
        try JSONDecoder().decode([GHPull].self, from: data).map {
            PullRequestItem(number: $0.number, title: $0.title, author: $0.author?.login ?? "", sourceBranch: $0.headRefName,
                            state: $0.state.lowercased(), isDraft: $0.isDraft ?? false, url: URL(string: $0.url), updatedAt: date($0.updatedAt))
        }
    }

    static func gitlab(_ data: Data) throws -> [PullRequestItem] {
        // glab prints nothing (not `[]`) for an empty list on some versions.
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A }) else { return [] }
        return try JSONDecoder().decode([GLMerge].self, from: data).map {
            PullRequestItem(number: $0.iid, title: $0.title, author: $0.author?.username ?? "", sourceBranch: $0.source_branch,
                            state: $0.state.lowercased(), isDraft: $0.draft ?? false, url: URL(string: $0.web_url), updatedAt: date($0.updated_at))
        }
    }
}
