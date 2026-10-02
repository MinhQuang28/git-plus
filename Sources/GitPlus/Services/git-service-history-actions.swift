import Foundation

/// Commit context-menu actions (mirrors GitHub Desktop's commit menu).
extension GitService {
    func reset(to hash: String, mode: ResetMode = .mixed) async throws { _ = try await git(["reset", "--\(mode.rawValue)", hash]) }
    func checkout(commit hash: String) async throws { _ = try await git(["switch", "--detach", hash]) }
    func createBranch(_ name: String, at hash: String) async throws { _ = try await git(["switch", "-c", name, hash]) }
    func createTag(_ name: String, at hash: String, message: String? = nil) async throws {
        if let message, !message.isEmpty {
            _ = try await git(["tag", "-a", name, "-m", message, hash])
        } else {
            _ = try await git(["tag", name, hash])
        }
    }

    func revert(_ commit: Commit) async throws {
        let mainline = commit.parents.count > 1 ? ["-m", "1"] : []
        _ = try await git(["revert", "--no-edit"] + mainline + [commit.hash])
    }

    /// Applies `hash` onto `branch`, then returns to the original branch.
    /// Requires a clean tree; aborts and restores the original branch on conflict.
    func cherryPick(_ hash: String, onto branch: String) async throws {
        guard await !hasUncommittedChanges else {
            throw CommandError(command: "cherry-pick", status: 1, stderr: "Commit, stash or discard your changes before cherry-picking.")
        }
        let original = try await git(["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await git(["switch", branch])
        do {
            _ = try await git(["cherry-pick", hash])
        } catch {
            _ = try? await git(["cherry-pick", "--abort"])
            _ = try? await git(["switch", original])
            throw error
        }
        _ = try await git(["switch", original])
    }

    func headHash() async -> String? {
        (try? await git(["rev-parse", "--verify", "-q", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commits only in HEAD (ahead) and only in `branch` (behind).
    func aheadBehind(_ branch: String) async -> (ahead: Int, behind: Int) {
        let out = (try? await git(["rev-list", "--left-right", "--count", "HEAD...\(branch)"])) ?? ""
        let n = out.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        return n.count == 2 ? (n[0], n[1]) : (0, 0)
    }
}
