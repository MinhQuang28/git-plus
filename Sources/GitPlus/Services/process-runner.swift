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
    static func run(_ tool: String, _ args: [String], in directory: URL? = nil) async throws -> String {
        let data = try await runData(tool, args, in: directory)
        return String(decoding: data, as: UTF8.self)
    }

    static func runData(_ tool: String, _ args: [String], in directory: URL? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(tool, args, in: directory) })
            }
        }
    }

    /// Returns true when `tool` is resolvable on PATH.
    static func isAvailable(_ tool: String) async -> Bool {
        (try? await run("/usr/bin/which", [tool])) != nil
    }

    private static func runBlocking(_ tool: String, _ args: [String], in directory: URL?) throws -> Data {
        let process = Process()
        if tool.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [tool] + args
        }
        process.environment = environment
        if let directory { process.currentDirectoryURL = directory }

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain stderr concurrently so a full pipe buffer can never deadlock the child.
        var errData = Data()
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errGroup.wait()

        guard process.terminationStatus == 0 else {
            throw CommandError(
                command: ([tool] + args).joined(separator: " "),
                status: process.terminationStatus,
                stderr: String(decoding: errData, as: UTF8.self)
            )
        }
        return outData
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
