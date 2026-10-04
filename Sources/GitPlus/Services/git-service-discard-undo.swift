import Foundation

/// Exact backup of some paths (worktree bytes + index entries) taken right before a discard,
/// so "Undo" can put every byte back — staged parts, unstaged parts and untracked files alike.
struct WorkingSnapshot: Sendable {
    /// Worktree content per repo-relative path; `nil` = the file did not exist.
    let files: [String: Data?]
    /// `git ls-files -s` records: "mode sha stage\tpath".
    let indexEntries: [String]
}

/// Carries the backup from a store operation to its Undo action (both run later, off the view).
final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: WorkingSnapshot?
    var value: WorkingSnapshot? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

extension GitService {
    func snapshot(_ paths: [String]) async throws -> WorkingSnapshot {
        var files: [String: Data?] = [:]
        for path in Set(paths) {
            files[path] = FileManager.default.fileExists(atPath: repo.appendingPathComponent(path).path)
                ? try Data(contentsOf: repo.appendingPathComponent(path)) : nil
        }
        let index = paths.isEmpty ? "" : try await git(["ls-files", "-s", "-z", "--"] + Array(Set(paths)))
        return WorkingSnapshot(files: files, indexEntries: index.split(separator: "\0").map(String.init))
    }

    func restore(_ snapshot: WorkingSnapshot) async throws {
        let fm = FileManager.default
        for (path, data) in snapshot.files {
            let url = repo.appendingPathComponent(path)
            if let data {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            } else if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
        let paths = Array(snapshot.files.keys)
        guard !paths.isEmpty else { return }
        _ = try await git(["update-index", "--force-remove", "--"] + paths)
        for entry in snapshot.indexEntries {
            // "100644 <sha> 0\tpath" → update-index --cacheinfo 100644,<sha>,path (stage-0 entries only).
            let parts = entry.split(separator: "\t", maxSplits: 1).map(String.init)
            let meta = parts.first?.split(separator: " ").map(String.init) ?? []
            guard parts.count == 2, meta.count == 3, meta[2] == "0" else { continue }
            _ = try await git(["update-index", "--add", "--cacheinfo", "\(meta[0]),\(meta[1]),\(parts[1])"])
        }
    }

    /// Discards `files` and returns the backup that undoes it.
    func discardWithBackup(_ files: [ChangedFile]) async throws -> WorkingSnapshot {
        let backup = try await snapshot(files.flatMap(\.pathspec))
        try await discard(files)
        return backup
    }
}
