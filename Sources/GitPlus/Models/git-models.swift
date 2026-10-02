import Foundation

/// Snapshot of `git status --porcelain=v2 --branch`.
struct RepoStatus: Hashable, Sendable {
    var branch: String = "?"
    var upstream: String?
    var ahead = 0
    var behind = 0
    var changedFiles = 0
    var remote: RemoteInfo?
    /// Modification time of FETCH_HEAD ("Last fetched … ago").
    var lastFetched: Date?
}

struct BranchList: Sendable {
    var current: String?
    var local: [String] = []
    var remote: [String] = []
}

struct Commit: Identifiable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let subject: String
    let refs: [String]
}

/// A commit tagged with the repository it came from (group activity timeline).
struct RepoCommit: Identifiable, Hashable, Sendable {
    var id: String { repoID.uuidString + commit.hash }
    let repoID: UUID
    let repoName: String
    let commit: Commit
}

/// Revision range to diff: `git diff base head`.
struct DiffTarget: Hashable, Sendable {
    /// Git's well-known empty tree object; used as base for root commits.
    static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    let base: String
    let head: String
    let title: String
    var isRange = false

    /// Single commit compared against its first parent.
    static func commit(_ c: Commit) -> DiffTarget {
        DiffTarget(base: c.parents.first ?? emptyTree, head: c.hash, title: "\(c.shortHash) \(c.subject)")
    }

    /// Several commits (ordered newest first) collapsed into one range.
    static func range(_ commits: [Commit]) -> DiffTarget? {
        guard let newest = commits.first, let oldest = commits.last else { return nil }
        if commits.count == 1 { return .commit(newest) }
        return DiffTarget(
            base: oldest.parents.first ?? emptyTree, head: newest.hash,
            title: "\(oldest.shortHash)…\(newest.shortHash) (\(commits.count) commits)",
            isRange: true
        )
    }
}

struct ChangedFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// Single-letter status: A, M, D, R, C, T.
    let status: String
    let path: String
    let oldPath: String?
    var additions: Int = 0
    var deletions: Int = 0
}

enum DiffLineKind: Sendable { case context, added, removed, hunk, meta }

struct DiffLine: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: DiffLineKind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
}

struct PullRequestItem: Identifiable, Hashable, Sendable {
    var id: Int { number }
    let number: Int
    let title: String
    let author: String
    let sourceBranch: String
    let state: String
    let isDraft: Bool
    let url: URL?
    let updatedAt: Date?
}
