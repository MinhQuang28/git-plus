import Foundation

/// PATH for git and its hooks, taken from the user's shell so hooks see the same
/// `node`, `pnpm`, `python`… as Terminal does.
///
/// A successful interactive-shell lookup is cached, but redone as soon as one of its
/// directories disappears (e.g. `nvm install` + `nvm uninstall` while the app is open).
/// A failed lookup (slow rc file, timeout) is retried on later commands instead of being
/// cached for the whole session, and meanwhile well-known toolchain locations fill the gap.
enum ShellPathResolver {
    private struct Cache {
        let paths: [String]
        let existing: [String]   // directories present when cached; one vanishing invalidates the cache
    }

    private static let lock = NSLock()
    private static let resolving = NSLock()   // one shell probe at a time, concurrent callers wait for it
    nonisolated(unsafe) private static var cache: Cache?
    nonisolated(unsafe) private static var failures = 0
    private static let maxFailures = 3
    private static let probeTimeout: TimeInterval = 5

    static func paths() -> [String] {
        if let paths = cachedPaths() { return paths }
        return resolving.withLock {
            cachedPaths() ?? resolve()
        }
    }

    private static func cachedPaths() -> [String]? {
        guard let cached = lock.withLock({ cache }), cached.existing.allSatisfy(exists) else { return nil }
        return cached.paths
    }

    private static func resolve() -> [String] {
        // Version managers (nvm, pyenv, …) are usually set up in `.zshrc`, which only
        // interactive shells read — so try `-ilc` first, then plain `-lc`.
        if let interactive = shellPath(flags: "-ilc") {
            store(interactive)
            return interactive
        }
        let fallback = (shellPath(flags: "-lc") ?? []) + toolchainDirectories()
        let giveUp = lock.withLock { failures += 1; return failures >= maxFailures }
        if giveUp { store(fallback) }   // stop paying the probe cost on every command
        return fallback
    }

    private static func store(_ paths: [String]) {
        lock.withLock { cache = Cache(paths: paths, existing: paths.filter(exists)) }
    }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
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
        // A misbehaving rc file must not hang the app.
        DispatchQueue.global().asyncAfter(deadline: .now() + probeTimeout) { if process.isRunning { process.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1].split(separator: ":").map(String.init)
    }

    /// Where version managers install node & friends; used when the shell could not be asked.
    static func toolchainDirectories(home: String = NSHomeDirectory(),
                                     env: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var dirs = [nvmDefaultBin(nvmDir: env["NVM_DIR"] ?? home + "/.nvm")].compactMap { $0 }
        dirs += ["/.volta/bin", "/.bun/bin", "/.asdf/shims", "/.local/share/mise/shims", "/Library/pnpm", "/Library/pnpm/bin"]
            .map { home + $0 }
        return dirs.filter(exists)
    }

    /// `bin` of nvm's default node: the version named in `alias/default` when installed, else the newest one.
    static func nvmDefaultBin(nvmDir: String) -> String? {
        let versions = nvmDir + "/versions/node"
        guard let installed = try? FileManager.default.contentsOfDirectory(atPath: versions),
              let newest = installed.sorted(by: { $0.compare($1, options: .numeric) == .orderedAscending }).last
        else { return nil }
        let alias = (try? String(contentsOfFile: nvmDir + "/alias/default", encoding: .utf8))
            .map { "v" + $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("v") }
        let chosen = alias.flatMap { a in installed.first { $0 == a || $0.hasPrefix(a + ".") } } ?? newest
        return versions + "/" + chosen + "/bin"
    }
}
