import XCTest
@testable import GitPlus

/// AI commit messages: file filtering, prompt, reply parsing, provider errors, and input gathering on real git.
final class AICommitMessageTests: XCTestCase {
    // MARK: Pure parts

    func testExcludesLockfilesGeneratedAndSecrets() {
        for path in ["package-lock.json", "web/yarn.lock", "Cargo.lock", "app/dist/main.js", "a/b.min.js", "x.js.map",
                     ".env", "config/.env.production", "certs/server.pem", "keys/id_ed25519", "node_modules/x/index.js"] {
            XCTAssertTrue(CommitMessagePrompt.isExcluded(path), path)
        }
        for path in ["config/secrets.yml", "aws-credentials.json", "infra/prod.tfvars", ".envrc", "config/master.key", "db.password"] {
            XCTAssertTrue(CommitMessagePrompt.isExcluded(path), path)
        }
        for path in ["src/app.ts", "README.md", "Sources/build-app.swift", "docs/environment.md", "lib/key-store.swift",
                     "Sources/secret-store.swift", "src/password-reset.tsx"] {
            XCTAssertFalse(CommitMessagePrompt.isExcluded(path), path)
        }
    }

    func testRedactsKnownTokenFormats() {
        let text = "+let key = \"sk-proj-abcdefghijklmnopqrstuvwxyz123456\"\n+aws = AKIAABCDEFGHIJKLMNOP\n+gh = ghp_" + String(repeating: "a", count: 36)
        let redacted = CommitMessagePrompt.redactSecrets(text)
        XCTAssertFalse(redacted.contains("sk-proj-abc"))
        XCTAssertFalse(redacted.contains("AKIAABCD"))
        XCTAssertFalse(redacted.contains("ghp_aaa"))
        XCTAssertEqual(redacted.components(separatedBy: "[REDACTED]").count - 1, 3)
        XCTAssertEqual(CommitMessagePrompt.redactSecrets("+let skip = 1"), "+let skip = 1")
    }

    func testRedactsValuesAssignedToSecretLikeKeys() {
        let cases: [(String, String)] = [
            ("+DB_PASSWORD=hunter2hunter2", "+DB_PASSWORD=[REDACTED]"),
            ("+  password: s3cr3t-value", "+  password: [REDACTED]"),
            (#"+  "client_secret": "abcd1234efgh","#, #"+  "client_secret": "[REDACTED]","#),
            (#"+const API_KEY = 'q1w2e3r4t5y6'"#, #"+const API_KEY = '[REDACTED]'"#),
            ("+DATABASE_URL=postgres://app:Sup3rS3cret@db:5432/x", "+DATABASE_URL=postgres://app:[REDACTED]@db:5432/x"),
            ("+Authorization: Bearer abcdefghijklmnop1234", "+Authorization: Bearer [REDACTED]"),
        ]
        for (input, expected) in cases { XCTAssertEqual(CommitMessagePrompt.redactSecrets(input), expected, input) }
        // Ordinary code stays readable.
        XCTAssertEqual(CommitMessagePrompt.redactSecrets("+func reset(user: User) {"), "+func reset(user: User) {")
        XCTAssertEqual(CommitMessagePrompt.redactSecrets("+let token = try await fetchToken()"), "+let token = try await fetchToken()")
    }

    func testUserMessageListsOmittedFilesAndFallsBackToStats() {
        var input = CommitMessagePrompt.Input(branch: "feature/ABC-12", recentSubjects: ["feat: add x"], intent: "speed up",
                                              stat: " a.swift | 2 +-\n", omitted: ["yarn.lock"], diff: nil)
        var message = CommitMessagePrompt.userMessage(input)
        XCTAssertTrue(message.contains("Branch: feature/ABC-12"))
        XCTAssertTrue(message.contains("- feat: add x"))
        XCTAssertTrue(message.contains("Author's intent: speed up"))
        XCTAssertTrue(message.contains("yarn.lock"))
        XCTAssertTrue(message.contains("too large"))
        input.diff = "+ok"
        message = CommitMessagePrompt.userMessage(input)
        XCTAssertTrue(message.hasSuffix("Diff:\n+ok"))
    }

    func testSystemPromptFollowsSettings() {
        XCTAssertTrue(CommitMessagePrompt.systemPrompt(language: .english, includeBody: true).contains("Write in English."))
        XCTAssertTrue(CommitMessagePrompt.systemPrompt(language: .vietnamese, includeBody: false).contains("only the summary line"))
    }

    func testParsesReplyVariants() {
        XCTAssertEqual(CommitMessagePrompt.parse("feat: add x\n\n- one\n- two"), .init(summary: "feat: add x", body: "- one\n- two"))
        XCTAssertEqual(CommitMessagePrompt.parse("```\nfix: y\n```"), .init(summary: "fix: y", body: ""))
        XCTAssertEqual(CommitMessagePrompt.parse("Commit message: \"docs: z\""), .init(summary: "docs: z", body: ""))
        XCTAssertNil(CommitMessagePrompt.parse("  \n```\n```"))
    }

    func testKeepsCoAuthorTrailers() {
        let previous = "old text\n\nCo-authored-by: A <a@x>"
        XCTAssertEqual(CommitMessagePrompt.details(body: "new body", keepingTrailersFrom: previous), "new body\n\nCo-authored-by: A <a@x>")
        XCTAssertEqual(CommitMessagePrompt.details(body: "", keepingTrailersFrom: previous), "Co-authored-by: A <a@x>")
        XCTAssertEqual(CommitMessagePrompt.details(body: "b", keepingTrailersFrom: ""), "b")
    }

    func testBaseURLValidation() {
        XCTAssertNotNil(AISettings.validatedBaseURL("https://api.deepseek.com"))
        XCTAssertEqual(AISettings.validatedBaseURL("https://api.openai.com/v1/")?.absoluteString, "https://api.openai.com/v1")
        XCTAssertNotNil(AISettings.validatedBaseURL("http://localhost:11434/v1"))
        XCTAssertNil(AISettings.validatedBaseURL("http://example.com/v1"))
        XCTAssertNil(AISettings.validatedBaseURL("https://user:pw@example.com"))
        XCTAssertNil(AISettings.validatedBaseURL("ftp://example.com"))
        XCTAssertNil(AISettings.validatedBaseURL(""))
    }

    // MARK: Provider replies (bodies in the shape DeepSeek / OpenAI return)

    func testReadsChatCompletionContent() throws {
        let ok = #"{"choices":[{"index":0,"message":{"role":"assistant","content":"feat: x","reasoning_content":"…"},"finish_reason":"stop"}]}"#
        XCTAssertEqual(try ChatCompletionClient.messageText(from: Data(ok.utf8)), "feat: x")
        let cut = #"{"choices":[{"message":{"content":""},"finish_reason":"length"}]}"#
        XCTAssertThrowsError(try ChatCompletionClient.messageText(from: Data(cut.utf8)))
    }

    func testMapsProviderErrors() {
        func map(_ status: Int, _ body: String, _ retry: String? = nil) -> AIError {
            ChatCompletionClient.error(status: status, body: Data(body.utf8), retryAfter: retry)
        }
        XCTAssertEqual(map(401, #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#),
                       .unauthorized("Incorrect API key provided"))
        XCTAssertEqual(map(402, #"{"error":{"message":"Insufficient Balance"}}"#), .paymentRequired("Insufficient Balance"))
        XCTAssertEqual(map(429, #"{"error":{"message":"slow down"}}"#, "12"), .rateLimited(retryAfter: 12))
        XCTAssertEqual(map(429, #"{"error":{"message":"quota","code":"insufficient_quota"}}"#), .paymentRequired("quota"))
        XCTAssertEqual(map(400, #"{"error":{"message":"Model Not Exist"}}"#), .modelNotFound("Model Not Exist"))
        XCTAssertEqual(map(404, #"{"error":{"message":"This model is only supported in v1/responses and not in v1/chat/completions."}}"#),
                       .responsesAPIOnly)
        XCTAssertEqual(map(503, "Service Unavailable"), .server(status: 503, message: "Service Unavailable"))
    }

    // MARK: Input gathering against real git

    func testCollectsStagedOrEverythingWithoutTouchingTheIndex() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func sh(_ args: [String]) async throws { _ = try await ProcessRunner.run("git", args, in: dir) }
        func write(_ name: String, _ text: String) throws { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "T"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            try await sh(args)
        }
        try write("a.txt", "one\n")
        try write("old.txt", "legacy content\n")
        try await sh(["add", "."])
        try await sh(["commit", "-qm", "feat: first"])

        try write("a.txt", "two\n")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("old.txt"))
        try write(".env", "SECRET=1\n")
        try write("new.txt", "fresh\n")
        let generator = CommitMessageGenerator(repo: dir, config: AIConfig(baseURL: URL(string: "https://example.com")!, model: "m", apiKey: "k"),
                                               language: .english, includeBody: true)

        // Nothing staged → describe everything, including untracked files; .env content is not sent.
        let all = try await generator.collectInput(intent: "", includeAll: true, statsOnly: false)
        XCTAssertEqual(all.branch, "main")
        XCTAssertEqual(all.recentSubjects, ["feat: first"])
        XCTAssertEqual(all.omitted, [".env"])
        XCTAssertTrue(all.diff?.contains("+two") == true)
        XCTAssertTrue(all.diff?.contains("+fresh") == true)
        XCTAssertFalse(all.diff?.contains("SECRET") == true)
        XCTAssertTrue(all.diff?.contains("deleted file mode") == true, "the deletion itself is still described")
        XCTAssertFalse(all.diff?.contains("legacy content") == true, "deleted files' old content is not sent")
        let staged = try await ProcessRunner.run("git", ["diff", "--cached", "--name-only"], in: dir)
        XCTAssertEqual(staged, "", "the real index must stay untouched")

        // Only what is staged.
        try await sh(["add", "new.txt"])
        let partial = try await generator.collectInput(intent: "", includeAll: false, statsOnly: false)
        XCTAssertTrue(partial.diff?.contains("+fresh") == true)
        XCTAssertFalse(partial.diff?.contains("+two") == true)

        let statsOnly = try await generator.collectInput(intent: "", includeAll: false, statsOnly: true)
        XCTAssertNil(statsOnly.diff)
        XCTAssertTrue(statsOnly.stat.contains("new.txt"))
    }
}
