import Foundation

struct CommandError: LocalizedError {
    let command: String
    let status: Int32
    let stderr: String
    /// Some git commands (stash apply, merge) report conflicts on stdout and leave stderr empty.
    var stdout = ""

    var errorDescription: String? {
        let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty { return msg }
        let lines = stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let important = lines.filter { line in ["CONFLICT", "error", "fatal", "warning"].contains { line.hasPrefix($0) } }
        let shown = important.isEmpty ? Array(lines.suffix(3)) : important
        return shown.isEmpty ? "`\(command)` exited with status \(status)" : shown.joined(separator: "\n")
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
    static func run(_ tool: String, _ args: [String], in directory: URL? = nil, okCodes: Set<Int32> = [0],
                    environment: [String: String] = [:]) async throws -> String {
        let data = try await runData(tool, args, in: directory, okCodes: okCodes, environment: environment)
        return String(decoding: data, as: UTF8.self)
    }

    /// `okCodes`: exit statuses treated as success (e.g. `git diff --no-index` exits 1 when files differ).
    /// Non-blocking (pipe readability + termination handlers, no parked threads) and cancellable:
    /// cancelling the calling task terminates the child process. `environment` adds/overrides variables.
    static func runData(_ tool: String, _ args: [String], in directory: URL? = nil, okCodes: Set<Int32> = [0],
                        environment: [String: String] = [:]) async throws -> Data {
        try Task.checkCancellation()
        let run = RunningProcess(tool, args, in: directory, environment: environment)
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in run.start(continuation) }
        } onCancel: {
            run.terminate()
        }
        try Task.checkCancellation()
        guard okCodes.contains(result.status) else {
            throw CommandError(command: ([tool] + args).joined(separator: " "), status: result.status,
                               stderr: String(decoding: result.stderr, as: UTF8.self),
                               stdout: String(decoding: result.stdout.suffix(4000), as: UTF8.self))
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

    /// Version managers (nvm, pyenv, …) are usually set up in `.zshrc`, which only interactive
    /// shells read — so try `-ilc` first (needed for hooks that call `node` etc.), then plain `-lc`.
    private static func loginShellPath() -> [String]? {
        shellPath(flags: "-ilc") ?? shellPath(flags: "-lc")
    }

    private static func shellPath(flags: String) -> [String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__GITPLUS_PATH__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Markers isolate PATH from anything rc files print to stdout.
        process.arguments = [flags, "printf '\(marker)%s\(marker)' \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A misbehaving rc file must not hang app startup.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1].split(separator: ":").map(String.init)
    }
}
