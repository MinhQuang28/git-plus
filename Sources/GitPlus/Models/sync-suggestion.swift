import Foundation

/// The next sync step for a repository, derived from its status (drives the sync button and status header).
enum SyncSuggestion: Equatable, Sendable {
    case noRemote
    case publish
    case fetch
    case pull(behind: Int)
    case push(ahead: Int)
    /// Local and remote both have new commits (also what an amended, already-pushed commit looks like).
    case diverged(ahead: Int, behind: Int)

    init(_ status: RepoStatus?) {
        guard let s = status else { self = .fetch; return }
        if s.remote == nil && s.upstream == nil { self = .noRemote; return }
        if s.upstream == nil { self = .publish; return }
        switch (s.ahead, s.behind) {
        case (0, 0): self = .fetch
        case (let a, 0): self = .push(ahead: a)
        case (0, let b): self = .pull(behind: b)
        case (let a, let b): self = .diverged(ahead: a, behind: b)
        }
    }

    var title: String {
        switch self {
        case .noRemote: "No Remote"
        case .publish: "Publish Branch"
        case .fetch: "Fetch"
        case .pull(let n): "Pull \(n)"
        case .push(let n): "Push \(n)"
        case .diverged(let a, let b): "Sync ↑\(a) ↓\(b)"
        }
    }

    var symbol: String {
        switch self {
        case .noRemote: "icloud.slash"
        case .publish, .push: "arrow.up.circle"
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down.circle"
        case .diverged: "arrow.up.arrow.down.circle"
        }
    }

    /// Needs the user's attention in the status header.
    var needsAttention: Bool {
        switch self {
        case .diverged, .publish: true
        default: false
        }
    }
}

/// Recognises common git failures and suggests a way out.
enum GitErrorHint: Equatable, Sendable {
    /// Push rejected because the remote has commits you don't have.
    case pushRejected
    /// `pull --ff-only` refused because the branches diverged.
    case diverged
    /// `--force-with-lease` refused: the remote moved since the last fetch.
    case staleLease
    case authentication
    /// Checkout / pull / merge would overwrite local changes.
    case localChanges
    case noUpstream
    case lockFile
    case conflicts
    case identity

    static func classify(_ message: String) -> GitErrorHint? {
        let m = message.lowercased()
        if m.contains("stale info") { return .staleLease }
        if m.contains("not possible to fast-forward") || m.contains("divergent branches") || m.contains("have diverged") { return .diverged }
        if m.contains("[rejected]") || m.contains("non-fast-forward") || m.contains("fetch first") || m.contains("updates were rejected") { return .pushRejected }
        if m.contains("authentication failed") || m.contains("could not read username") || m.contains("permission denied (publickey")
            || m.contains("could not read from remote repository") || m.contains("terminal prompts disabled") { return .authentication }
        if m.contains("would be overwritten") || m.contains("commit your changes or stash them") || m.contains("please commit or stash") { return .localChanges }
        if m.contains("has no upstream branch") || m.contains("no tracking information") { return .noUpstream }
        if m.contains("index.lock") || (m.contains("unable to create") && m.contains(".lock")) { return .lockFile }
        if m.contains("conflict") && (m.contains("merge conflict") || m.contains("could not apply") || m.contains("fix conflicts")) { return .conflicts }
        if m.contains("please tell me who you are") || m.contains("empty ident") { return .identity }
        return nil
    }

    var explanation: String {
        switch self {
        case .pushRejected: "The remote has commits you don't have yet. Pull them first, then push again."
        case .diverged: "Your branch and its upstream have both moved on. Integrate the remote commits with a rebase or a merge."
        case .staleLease: "The remote branch changed since your last fetch, so the force push was refused to protect those commits. Fetch, review, then try again."
        case .authentication: "Git could not authenticate. Git Plus never shows password prompts — set up an SSH key or a credential helper (for GitHub: `gh auth setup-git`), then retry."
        case .localChanges: "Your uncommitted changes would be overwritten. Commit or stash them first."
        case .noUpstream: "This branch is not published yet."
        case .lockFile: "Another git process is running in this repository (or crashed and left `.git/index.lock`). Wait for it to finish, or delete the lock file if no git process is running."
        case .conflicts: "Some changes conflict. Resolve the conflicted files in the Changes tab, then continue."
        case .identity: "Git doesn't know who you are. Run `git config --global user.name \"Your Name\"` and `git config --global user.email you@example.com`."
        }
    }
}
