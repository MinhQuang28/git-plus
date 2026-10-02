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
    /// Merge / rebase / cherry-pick / revert waiting to be continued or aborted.
    var operation: GitOperation?
    var conflicts = 0
}

/// A multi-step git operation that stopped (usually on conflicts).
enum GitOperation: String, Sendable {
    case merge, rebase, cherryPick = "cherry-pick", revert

    var title: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .cherryPick: "Cherry-pick"
        case .revert: "Revert"
        }
    }
}

enum ResetMode: String, CaseIterable, Sendable {
    case soft, mixed, hard

    var summary: String {
        switch self {
        case .soft: "Keep all changes staged"
        case .mixed: "Keep changes in the working directory (unstaged)"
        case .hard: "Discard all changes — cannot be undone"
        }
    }
}

struct StashEntry: Identifiable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    /// `stash@{n}` at load time.
    let ref: String
    let message: String
    let date: Date
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

/// Which part of the working tree a change belongs to (`.revision` for commit diffs).
enum ChangeArea: String, Sendable { case revision, staged, unstaged, conflicted }

struct ChangedFile: Identifiable, Hashable, Sendable {
    var id: String { area == .revision ? path : "\(area.rawValue):\(path)" }
    /// Single-letter status: A, M, D, R, C, T, ? (untracked), U (conflict).
    let status: String
    let path: String
    let oldPath: String?
    var additions: Int = 0
    var deletions: Int = 0
    var area: ChangeArea = .revision
    /// Two-letter porcelain code for conflicts (`UU`, `AA`, `DU`, `UD`, `AU`, `UA`, `DD`).
    var conflictCode: String? = nil

    /// Paths to pass to git (both sides of a rename).
    var pathspec: [String] { [oldPath, path].compactMap { $0 } }
    /// Hunk/line staging only makes sense for modifications of existing files.
    var supportsPartialStaging: Bool { status == "M" && (area == .staged || area == .unstaged) }

    /// For conflicts: the side that deleted the file (its version does not exist), if any.
    var deletedSide: ConflictSide? {
        switch conflictCode {
        case "DU", "UA": .ours     // deleted by us / added only by them
        case "UD", "AU": .theirs   // deleted by them / added only by us
        default: nil
        }
    }
}

enum ConflictSide: Sendable { case ours, theirs }

struct WorkingTree: Sendable {
    var staged: [ChangedFile] = []
    var unstaged: [ChangedFile] = []
    var conflicted: [ChangedFile] = []

    var all: [ChangedFile] { conflicted + staged + unstaged }
    var isEmpty: Bool { staged.isEmpty && unstaged.isEmpty && conflicted.isEmpty }
    var count: Int { Set(all.map(\.path)).count }
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
