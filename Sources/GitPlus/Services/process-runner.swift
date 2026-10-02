import Foundation

struct CommandError: LocalizedError {
    let command: String
    let status: Int32
    let stderr: String

    var errorDescription: String? {
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "`\(command)` exited with status \(status)" : msg
    }
}

/// Runs CLI tools (git, gh, glab) as subprocesses.
///
/// GUI apps launched from Finder get a minimal PATH, so the user's login-shell PATH
/// is resolved once and merged with common Homebrew locations. This keeps behaviour
/// identical to what the user sees in Terminal (same git config, hooks, credential helpers).
enum ProcessRunner {
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let fallback = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var paths = loginShellPath() ?? []
        paths += (env["PATH"] ?? "").split(separator: ":").map(String.init)
        paths += fallback
        var seen = Set<String>()
        env["PATH"] = paths.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"   // never block on credential prompts
        env["GIT_OPTIONAL_LOCKS"] = "0"    // read-only commands must not fight with other git clients
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        env["PAGER"] = "cat"
        return env
    }()

    /// Runs `tool args…` in `directory`; returns stdout or throws `CommandError` on non-zero exit.
    static func run(_ tool: String, _ args: [String], in directory: URL? = nil, okCodes: Set<Int32> = [0]) async throws -> String {
        let data = try await runData(tool, args, in: directory, okCodes: okCodes)
        return String(decoding: data, as: UTF8.self)
    }

    /// `okCodes`: exit statuses treated as success (e.g. `git diff --no-index` exits 1 when files differ).
    /// Non-blocking (pipe readability + termination handlers, no parked threads) and cancellable:
    /// cancelling the calling task terminates the child process.
    static func runData(_ tool: String, _ args: [String], in directory: URL? = nil, okCodes: Set<Int32> = [0]) async throws -> Data {
        try Task.checkCancellation()
        let run = RunningProcess(tool, args, in: directory)
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in run.start(continuation) }
        } onCancel: {
            run.terminate()
        }
        try Task.checkCancellation()
        guard okCodes.contains(result.status) else {
            throw CommandError(command: ([tool] + args).joined(separator: " "), status: result.status,
                               stderr: String(decoding: result.stderr, as: UTF8.self))
        }
        return result.stdout
    }

    private static let availabilityLock = NSLock()
    nonisolated(unsafe) private static var available: Set<String> = []

    /// Returns true when `tool` is resolvable on PATH. Found tools are remembered (one `which` per tool);
    /// missing ones are re-checked, so installing `gh` takes effect without a restart.
    static func isAvailable(_ tool: String) async -> Bool {
        if availabilityLock.withLock({ available.contains(tool) }) { return true }
        let found = (try? await run("/usr/bin/which", [tool])) != nil
        if found { availabilityLock.withLock { _ = available.insert(tool) } }
        return found
    }

    private static func loginShellPath() -> [String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: ":").map(String.init)
    }
}
