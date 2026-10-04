import XCTest
@testable import GitPlus

/// Every discard is backed up first; restoring the backup must put index and worktree back exactly.
final class DiscardUndoTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "T"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            try await sh(args)
        }
        try write("a.txt", "one\n")
        try await sh(["add", "."])
        try await sh(["commit", "-qm", "base"])
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func sh(_ args: [String]) async throws { _ = try await ProcessRunner.run("git", args, in: dir) }
    private func write(_ name: String, _ text: String) throws {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    private func read(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
    private func staged(_ name: String) async throws -> String { try await GitService(repo: dir).git(["show", ":\(name)"]) }

    func testUndoRestoresStagedAndUnstagedPartsAndUntrackedFiles() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "one\nstaged\n")
        try await sh(["add", "a.txt"])
        try write("a.txt", "one\nstaged\nunstaged\n")
        try write("dir/new.txt", "untracked\n")

        let tree = try await git.workingTree()
        let files = tree.staged + tree.unstaged
        let backup = try await git.discardWithBackup(files)
        XCTAssertEqual(read("a.txt"), "one\n")
        XCTAssertNil(read("dir/new.txt"))

        try await git.restore(backup)
        XCTAssertEqual(read("a.txt"), "one\nstaged\nunstaged\n")
        XCTAssertEqual(read("dir/new.txt"), "untracked\n")
        let index = try await staged("a.txt")
        XCTAssertEqual(index, "one\nstaged\n")
        let untrackedStillUntracked = try await git.workingTree().unstaged.contains { $0.path == "dir/new.txt" && $0.status == "?" }
        XCTAssertTrue(untrackedStillUntracked)
    }

    func testUndoOfUnstagedOnlyDiscardKeepsStagedPart() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "one\nstaged\n")
        try await sh(["add", "a.txt"])
        try write("a.txt", "one\nstaged\nunstaged\n")

        let unstaged = try await git.workingTree().unstaged
        let backup = try await git.discardWithBackup(unstaged)
        XCTAssertEqual(read("a.txt"), "one\nstaged\n")

        try await git.restore(backup)
        XCTAssertEqual(read("a.txt"), "one\nstaged\nunstaged\n")
        let index = try await staged("a.txt")
        XCTAssertEqual(index, "one\nstaged\n")
    }

    func testUndoOfNewlyAddedFile() async throws {
        let git = GitService(repo: dir)
        try write("b.txt", "added\n")
        try await sh(["add", "b.txt"])
        let staged = try await git.workingTree().staged
        let backup = try await git.discardWithBackup(staged)
        try await git.restore(backup)
        XCTAssertEqual(read("b.txt"), "added\n")
        let isStaged = try await git.workingTree().staged.contains { $0.path == "b.txt" && $0.status == "A" }
        XCTAssertTrue(isStaged)
    }
}
