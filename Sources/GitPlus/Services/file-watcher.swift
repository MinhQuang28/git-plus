import CoreServices
import Foundation

/// Watches a repository folder with FSEvents and reports the changed paths, so the open repository
/// refreshes when files are edited outside Git Plus.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void
    private let root: String

    /// Paths whose churn says nothing about the repository state (git internals, common build output).
    private static let ignoredFragments = [
        "/.git/objects/", "/.git/logs/", "/.git/lfs/", "/node_modules/", "/.build/", "/DerivedData/", "/build/",
        "/dist/", "/target/", "/.next/", "/.nuxt/", "/.gradle/", "/.venv/", "/venv/", "/__pycache__/", "/.cache/",
        "/.turbo/", "/coverage/", "/Pods/", "/.DS_Store",
    ]

    init(folder: URL, latency: TimeInterval = 0.6, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        root = folder.standardizedFileURL.path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            watcher.handle(Array(changed.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ paths: [String]) {
        let relevant = paths.filter { path in
            !Self.ignoredFragments.contains { path.contains($0) } && !path.hasSuffix(".lock") && !path.hasSuffix("/.git/FETCH_HEAD")
        }
        if !relevant.isEmpty { onChange(relevant) }
    }

    /// Whether a change can affect history (branches, HEAD) rather than only the working tree / index.
    static func affectsHistory(_ path: String) -> Bool {
        path.contains("/.git/HEAD") || path.contains("/.git/refs/") || path.contains("/.git/packed-refs")
            || path.contains("/.git/rebase-") || path.hasSuffix("/.git/MERGE_HEAD") || path.hasSuffix("/.git/ORIG_HEAD")
    }

    static func isGitInternal(_ path: String) -> Bool { path.contains("/.git/") || path.hasSuffix("/.git") }
}
