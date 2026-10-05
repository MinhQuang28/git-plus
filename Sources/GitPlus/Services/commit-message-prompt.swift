import Foundation

/// Pure building blocks of the AI commit message: which files may be sent, the prompt, and parsing the reply.
enum CommitMessagePrompt {
    /// Diffs above this are not sent (and never silently cut); the user can fall back to file names only.
    static let maxDiffBytes = 200_000

    struct Input {
        var branch: String?
        var recentSubjects: [String] = []
        var intent = ""
        var stat = ""
        var omitted: [String] = []
        /// nil → only file names and stats are sent.
        var diff: String?
    }

    struct Message: Equatable {
        let summary: String
        let body: String
    }

    // MARK: Files that never leave the machine as content

    private static let lockfiles: Set<String> = [
        "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "composer.lock",
        "gemfile.lock", "podfile.lock", "cargo.lock", "poetry.lock", "pipfile.lock", "go.sum", "package.resolved",
    ]
    private static let secretNames: Set<String> = [".npmrc", ".pypirc", ".netrc", "credentials", ".htpasswd"]
    private static let secretExtensions: Set<String> = ["pem", "key", "p12", "pfx", "keystore", "jks", "p8", "mobileprovision"]
    private static let generatedFolders: Set<String> = ["node_modules", "dist", "build", ".next", "coverage", "DerivedData"]

    /// Lockfiles, minified/generated output and likely secrets: listed by name only, content not sent.
    static func isExcluded(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        let folders = path.split(separator: "/").dropLast().map(String.init)
        if lockfiles.contains(name) || ext == "lock" { return true }
        if name.contains(".min.") || ext == "map" { return true }
        if folders.contains(where: generatedFolders.contains) { return true }
        if name.hasPrefix(".env") || secretNames.contains(name) || secretExtensions.contains(ext) { return true }
        if ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"].contains(where: name.hasPrefix) { return true }
        return false
    }

    /// Masks well-known credential formats that slipped into ordinary files.
    static func redactSecrets(_ text: String) -> String {
        let patterns = [
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
            #"\bsk-(?:proj-|ant-)?[A-Za-z0-9_\-]{20,}"#,      // OpenAI / Anthropic / DeepSeek keys
            #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#,                  // AWS access key id
            #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#,                 // GitHub tokens
            #"\bglpat-[A-Za-z0-9_\-]{20,}\b"#,                  // GitLab tokens
            #"\bxox[abpr]-[A-Za-z0-9\-]{10,}\b"#,               // Slack tokens
            #"\bshp(?:at|ca|pa|ss)_[a-fA-F0-9]{32}\b"#,         // Shopify tokens
        ]
        return patterns.reduce(text) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "[REDACTED]", options: .regularExpression)
        }
    }

    // MARK: Prompt

    static func systemPrompt(language: AIMessageLanguage, includeBody: Bool) -> String {
        let languageRule = switch language {
        case .english: "Write in English."
        case .vietnamese: "Write in Vietnamese; keep the Conventional Commit type, scopes and code identifiers as they are."
        case .matchHistory: "Write in the same language as the recent commits (English if there are none)."
        }
        let bodyRule = includeBody
            ? """
              After the summary, add a blank line and a short body that explains what changed and why, wrapped at \
              72 columns. Use "- " bullets for several independent changes. Leave the body out when the summary says it all.
              """
            : "Write only the summary line, no body."
        return """
        You write git commit messages from a diff.
        - First line: a summary in the imperative mood ("Add", "Fix", not "Added"), at most 72 characters \
        (aim for 50), no trailing period.
        - If the recent commits use Conventional Commits ("type(scope): …"), use that format with a fitting \
        type, reusing an existing scope when one fits. Otherwise follow the style of the recent commits.
        - \(bodyRule)
        - \(languageRule)
        - Describe only what the changes show. Do not invent motives, issue numbers or details.
        - If the author states an intent, build the message around it.
        - Reply with the commit message only: no quotes, no code fences, no explanations.
        """
    }

    static func userMessage(_ input: Input) -> String {
        var parts: [String] = []
        if let branch = input.branch, !branch.isEmpty { parts.append("Branch: \(branch)") }
        if !input.recentSubjects.isEmpty {
            parts.append("Recent commits (newest first):\n" + input.recentSubjects.map { "- \($0)" }.joined(separator: "\n"))
        }
        let intent = input.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !intent.isEmpty { parts.append("Author's intent: \(intent)") }
        parts.append("Changed files:\n\(input.stat.trimmingCharacters(in: .newlines))")
        if !input.omitted.isEmpty {
            parts.append("Content not included (lockfiles, generated, binary or secret files): " + input.omitted.joined(separator: ", "))
        }
        if let diff = input.diff {
            if !diff.isEmpty { parts.append("Diff:\n\(redactSecrets(diff))") }
        } else {
            parts.append("The diff is too large to include; describe the change from the file list.")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: Reply

    /// Strips code fences, wrapping quotes and a "Commit message:" label; first line is the summary.
    static func parse(_ reply: String) -> Message? {
        var lines = reply.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["commit message:", "summary:"] where text.lowercased().hasPrefix(label) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for quote in ["\"", "'", "`"] where text.count > 1 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let split = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = split.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        let body = split.count > 1 ? split[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return Message(summary: first, body: body)
    }

    /// New description: the generated body plus `Co-authored-by:` trailers the user had already added.
    static func details(body: String, keepingTrailersFrom previous: String) -> String {
        let trailers = previous.components(separatedBy: "\n").filter { $0.hasPrefix("Co-authored-by:") && !body.contains($0) }
        guard !trailers.isEmpty else { return body }
        return (body.isEmpty ? "" : body + "\n\n") + trailers.joined(separator: "\n")
    }
}
