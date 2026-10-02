import Foundation

/// How `git pull` integrates remote commits.
enum PullMode: String, CaseIterable, Sendable {
    case fastForward, rebase, merge

    var title: String {
        switch self {
        case .fastForward: "Fast-forward only"
        case .rebase: "Rebase"
        case .merge: "Merge"
        }
    }

    var args: [String] {
        switch self {
        case .fastForward: ["--ff-only"]
        case .rebase: ["--rebase"]
        case .merge: ["--no-rebase", "--no-edit"]
        }
    }
}

struct TagInfo: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let target: String
    let date: Date?
    let subject: String
}

struct RemoteEntry: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    var fetchURL: String
    var pushURL: String
}

/// One line of `git blame --porcelain`.
struct BlameLine: Identifiable, Hashable, Sendable {
    var id: Int { number }
    let number: Int
    let hash: String
    let author: String
    let date: Date
    let summary: String
    let text: String

    var shortHash: String { String(hash.prefix(7)) }
    /// Lines not yet committed are attributed to the all-zero hash.
    var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
}

/// A commit in a file's history together with the file's path (and status) in that commit.
struct FileRevision: Identifiable, Hashable, Sendable {
    var id: String { commit.hash }
    let commit: Commit
    let file: ChangedFile
}

/// One line of an interactive rebase todo list.
struct RebaseStep: Identifiable, Hashable, Sendable {
    enum Action: String, CaseIterable, Sendable {
        case pick, reword, squash, fixup, drop

        var title: String {
            switch self {
            case .pick: "Pick"
            case .reword: "Reword"
            case .squash: "Squash"
            case .fixup: "Fixup"
            case .drop: "Drop"
            }
        }

        /// Folds into the previous kept commit.
        var meldsIntoPrevious: Bool { self == .squash || self == .fixup }
    }

    var id: String { commit.hash }
    let commit: Commit
    var action: Action = .pick
    /// New message for `.reword`.
    var message = ""

    /// Validates a todo list (oldest first). Returns a user-facing problem, or nil when it can run.
    static func problem(_ steps: [RebaseStep]) -> String? {
        let kept = steps.filter { $0.action != .drop }
        guard !kept.isEmpty else { return "At least one commit must be kept." }
        if kept.first?.action.meldsIntoPrevious == true {
            return "The first kept commit cannot be squashed or fixed up — there is nothing before it to combine with."
        }
        if steps.contains(where: { $0.action == .reword && $0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Reworded commits need a message."
        }
        return nil
    }
}
