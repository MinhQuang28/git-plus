import CoreServices
import Foundation

/// Watches a repository folder with FSEvents and reports (debounced) that something changed,
/// so the open repository refreshes when files are edited outside Git Plus.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let root: String

    /// Paths whose churn says nothing about the repository state.
    private static let ignoredFragments = ["/.git/objects/", "/.git/logs/", "/node_modules/", "/.build/", "/DerivedData/", "/build/"]

    init(folder: URL, latency: TimeInterval = 0.6, onChange: @escaping () -> Void) {
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
        let relevant = paths.contains { path in
            !Self.ignoredFragments.contains { path.contains($0) } && !path.hasSuffix(".lock") && !path.hasSuffix("/.git/FETCH_HEAD")
        }
        if relevant { onChange() }
    }
}
