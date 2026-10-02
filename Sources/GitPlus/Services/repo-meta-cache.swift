import Foundation

/// Per-repository facts that rarely change, cached so a status refresh is one `git status` process:
/// the git dir / FETCH_HEAD path (fixed for a checkout) and remote URLs (re-read when `config` changes).
enum RepoMetaCache {
    struct Meta: Sendable {
        var gitDir: String?
        var fetchHead: String?
        var configPath: String?
        var configModified: Date?
        var remotes: [(name: String, url: String)] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Meta] = [:]

    static func meta(for git: GitService) async -> Meta {
        let key = git.repo.standardizedFileURL.path
        var meta = lock.withLock { cache[key] } ?? Meta()
        if meta.gitDir == nil {
            let out = (try? await git.git(["rev-parse", "--absolute-git-dir", "--git-path", "FETCH_HEAD", "--git-common-dir"])) ?? ""
            let lines = out.split(separator: "\n").map(String.init)
            func absolute(_ p: String) -> String { p.hasPrefix("/") ? p : git.repo.appendingPathComponent(p).path }
            if lines.count >= 3 {
                meta.gitDir = lines[0]
                meta.fetchHead = absolute(lines[1])
                meta.configPath = URL(fileURLWithPath: absolute(lines[2])).appendingPathComponent("config").path
            }
        }
        let modified = meta.configPath.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
        if meta.configModified == nil || modified != meta.configModified {
            meta.remotes = await git.remoteURLs()
            meta.configModified = modified
        }
        let result = meta
        lock.withLock { cache[key] = result }
        return result
    }

    /// Forget a repository's cached facts (e.g. after removing or re-adding it).
    static func invalidate(_ repo: URL) {
        _ = lock.withLock { cache.removeValue(forKey: repo.standardizedFileURL.path) }
    }
}
