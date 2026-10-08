import XCTest
@testable import GitPlus

/// Stash apply/pop edge cases and the "is there anything to push?" check, against real git.
final class StashConflictTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-stash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "T"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            try await sh(args)
        }
        try write("a.txt", "base\n")
        try write("b.txt", "b\n")
        try await sh(["add", "."])
        try await sh(["commit", "-qm", "base"])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir.appendingPathExtension("remote"))
    }

    private func sh(_ args: [String]) async throws { _ = try await ProcessRunner.run("git", args, in: dir) }
    private func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func read(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }

    func testApplyFallsBackWhenIndexCannotBeRestored() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "stashed\n")
        try await sh(["add", "a.txt"])            // staged part of the stash
        try write("b.txt", "worktree\n")
        try await git.stash(message: "work", includeUntracked: true)
        try write("a.txt", "mine\n")
        try await sh(["add", "a.txt"])            // index now differs → `--index` refuses to apply anything

        let stash = try await git.stashes()[0]
        do {
            try await git.applyStash(stash, pop: false)
            XCTFail("a.txt conflicts, apply must exit 1")
        } catch let error as CommandError {
            XCTAssertFalse(error.stderr.lowercased().contains("try without --index"), "the plain apply must have run")
            XCTAssertEqual(error.status, 1, "conflicts: git reports them on stdout and exits 1")
            XCTAssertTrue(error.localizedDescription.contains("CONFLICT"), "stdout-only reports must still reach the user")
            XCTAssertEqual(GitErrorHint.classify(error.localizedDescription), .conflicts)
        }
        let status = try await git.status()
        XCTAssertEqual(status.conflicts, 1)
        XCTAssertEqual(read("b.txt"), "worktree\n", "the non-conflicting file was applied")
        let kept = try await git.stashes()
        XCTAssertEqual(kept.count, 1, "git keeps the stash on conflict")

        let sides = await git.conflictSides(nil)
        XCTAssertEqual(sides.ours, "main")
        XCTAssertEqual(sides.theirs, "stash")
    }

    func testApplyRestoresIndexOnCleanTree() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "staged\n")
        try await sh(["add", "a.txt"])
        try write("b.txt", "unstaged\n")
        try await git.stash(message: "work", includeUntracked: true)
        try await git.applyStash(try await git.stashes()[0], pop: true)
        let tree = try await git.workingTree()
        XCTAssertEqual(tree.staged.map(\.path), ["a.txt"])
        XCTAssertEqual(tree.unstaged.map(\.path), ["b.txt"])
        let left = try await git.stashes()
        XCTAssertTrue(left.isEmpty)
    }

    func testUnpushedCountFollowsUpstream() async throws {
        let git = GitService(repo: dir)
        let noUpstream = await git.unpushedCount()
        XCTAssertNil(noUpstream)

        let remote = dir.appendingPathExtension("remote")
        _ = try await ProcessRunner.run("git", ["clone", "-q", "--bare", dir.path, remote.path])
        try await sh(["remote", "add", "origin", remote.path])
        try await sh(["push", "-q", "-u", "origin", "main"])
        let upToDate = await git.unpushedCount()
        XCTAssertEqual(upToDate, 0)

        // Staged but uncommitted work is not pushable.
        try write("a.txt", "resolved\n")
        try await sh(["add", "a.txt"])
        let stagedOnly = await git.unpushedCount()
        XCTAssertEqual(stagedOnly, 0)

        try await sh(["commit", "-qm", "resolved"])
        let afterCommit = await git.unpushedCount()
        XCTAssertEqual(afterCommit, 1)
    }
}
