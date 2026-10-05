import Foundation

/// Collects what the commit button would commit and asks the configured AI service for a message.
struct CommitMessageGenerator: Sendable {
    let repo: URL
    let config: AIConfig
    let language: AIMessageLanguage
    let includeBody: Bool

    /// `includeAll`: nothing is staged, so the commit will stage everything — describe the whole working
    /// tree (via a throwaway copy of the index; the real index is untouched).
    /// `statsOnly`: send file names and stats only (after `diffTooLarge`).
    func generate(intent: String, includeAll: Bool, statsOnly: Bool) async throws -> CommitMessagePrompt.Message {
        let input = try await collectInput(intent: intent, includeAll: includeAll, statsOnly: statsOnly)
        try Task.checkCancellation()
        let reply = try await ChatCompletionClient(config: config).complete(
            system: CommitMessagePrompt.systemPrompt(language: language, includeBody: includeBody),
            user: CommitMessagePrompt.userMessage(input))
        guard let message = CommitMessagePrompt.parse(reply) else { throw AIError.badResponse("no commit message in the reply") }
        return includeBody ? message : .init(summary: message.summary, body: "")
    }

    /// Everything the prompt needs, read from git (no network).
    func collectInput(intent: String, includeAll: Bool, statsOnly: Bool) async throws -> CommitMessagePrompt.Input {
        let tempIndex = includeAll ? try await makeFullIndex() : nil
        defer { if let tempIndex { try? FileManager.default.removeItem(at: tempIndex) } }
        let env = tempIndex.map { ["GIT_INDEX_FILE": $0.path] } ?? [:]
        func git(_ args: [String]) async throws -> String { try await ProcessRunner.run("git", args, in: repo, environment: env) }

        let files = Self.parseNumstat(try await git(["diff", "--cached", "--numstat", "-z"]))
        guard !files.isEmpty else { throw AIError.nothingToDescribe }
        let omitted = files.filter { $0.binary || CommitMessagePrompt.isExcluded($0.path) }.map(\.path)

        var input = CommitMessagePrompt.Input(omitted: omitted)
        input.intent = intent
        input.stat = try await git(["diff", "--cached", "--stat=120", "--no-color", "-M"])
        if !statsOnly {
            if omitted.count == files.count {
                input.diff = ""
            } else {
                let excludes = omitted.map { ":(exclude,literal)\($0)" }
                let diff = try await git(["diff", "--cached", "-M", "--no-color", "--no-ext-diff", "-U3", "--", "."] + excludes)
                let size = diff.utf8.count
                guard size <= CommitMessagePrompt.maxDiffBytes else { throw AIError.diffTooLarge(bytes: size) }
                input.diff = diff
            }
        }
        // Both fail on an unborn branch (no commits yet); that's fine.
        input.branch = (try? await git(["symbolic-ref", "--short", "-q", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        input.recentSubjects = ((try? await git(["log", "-n", "20", "--no-merges", "--format=%s"])) ?? "")
            .split(separator: "\n").map(String.init)
        return input
    }

    /// Copy of the index with every change added (`git add -A`), as the commit button would do.
    private func makeFullIndex() async throws -> URL {
        let indexPath = try await ProcessRunner.run("git", ["rev-parse", "--git-path", "index"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let index = URL(fileURLWithPath: indexPath, relativeTo: repo).standardizedFileURL
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-ai-\(UUID().uuidString).index")
        if FileManager.default.fileExists(atPath: index.path) { try FileManager.default.copyItem(at: index, to: temp) }
        do {
            _ = try await ProcessRunner.run("git", ["add", "-A"], in: repo, environment: ["GIT_INDEX_FILE": temp.path])
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return temp
    }

    /// `git diff --numstat -z` → paths, with binary files marked (`-\t-\tpath`).
    static func parseNumstat(_ output: String) -> [(path: String, binary: Bool)] {
        output.split(separator: "\0").compactMap { record in
            let cols = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count == 3, !cols[2].isEmpty else { return nil }
            return (String(cols[2]), cols[0] == "-" && cols[1] == "-")
        }
    }
}
