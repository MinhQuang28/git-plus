import Foundation

/// One child process driven entirely by callbacks: stdout/stderr are drained by readability handlers
/// and completion waits for both EOFs plus exit, so no thread blocks while git runs.
final class RunningProcess: @unchecked Sendable {
    struct Output: Sendable {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    private let process = Process()
    private let out = Pipe(), err = Pipe()
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    private var pending = 3                     // stdout EOF, stderr EOF, exit
    private var continuation: CheckedContinuation<Output, Error>?
    private var cancelled = false

    init(_ tool: String, _ args: [String], in directory: URL?, environment extra: [String: String] = [:]) {
        if tool.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [tool] + args
        }
        process.environment = ProcessRunner.environment.merging(extra) { _, new in new }
        if let directory { process.currentDirectoryURL = directory }
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
    }

    func start(_ continuation: CheckedContinuation<Output, Error>) {
        let alreadyCancelled = lock.withLock { () -> Bool in
            self.continuation = continuation
            return cancelled
        }
        if alreadyCancelled { return finish(throwing: CancellationError()) }

        // Strong captures keep this object alive until the process finishes; `done()` breaks the cycle.
        out.fileHandleForReading.readabilityHandler = { h in self.read(h, isStdout: true) }
        err.fileHandleForReading.readabilityHandler = { h in self.read(h, isStdout: false) }
        process.terminationHandler = { _ in self.done() }
        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            finish(throwing: error)
        }
    }

    func terminate() {
        let running = lock.withLock { () -> Bool in
            cancelled = true
            return process.isRunning
        }
        if running { process.terminate() }
    }

    private func read(_ handle: FileHandle, isStdout: Bool) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            done()
            return
        }
        lock.withLock { isStdout ? stdout.append(chunk) : stderr.append(chunk) }
    }

    private func done() {
        let output: Output? = lock.withLock {
            pending -= 1
            guard pending == 0 else { return nil }
            return Output(stdout: stdout, stderr: stderr, status: process.terminationStatus)
        }
        guard let output else { return }
        process.terminationHandler = nil
        let c = lock.withLock { () -> CheckedContinuation<Output, Error>? in defer { continuation = nil }; return continuation }
        c?.resume(returning: output)
    }

    private func finish(throwing error: Error) {
        let c = lock.withLock { () -> CheckedContinuation<Output, Error>? in defer { continuation = nil }; return continuation }
        c?.resume(throwing: error)
    }
}
