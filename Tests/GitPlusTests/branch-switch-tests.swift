import XCTest
@testable import GitPlus

/// "Leave my changes on <branch>" vs "bring them along" when switching branches, against real git.
final class BranchSwitchTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-switch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "dev"], ["config", "user.name", "T"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            try await sh(args)
        }
        try write("a.txt", "base\n")
        try await sh(["add", "."])
        try await sh(["commit", "-qm", "base"])
        try await sh(["branch", "prod"])
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func sh(_ args: [String]) async throws { _ = try await ProcessRunner.run("git", args, in: dir) }
    private func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func read(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
    private func branch(_ git: GitService) async throws -> String { try await git.status().branch }

    func testLeaveChangesStashesAndRestoresOnReturn() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "edited on dev\n")
        try write("new.txt", "untracked\n")

        try await git.switchBranch("prod", leaveChangesOn: "dev")
        let onProd = try await branch(git)
        XCTAssertEqual(onProd, "prod")
        XCTAssertEqual(read("a.txt"), "base\n")
        XCTAssertNil(read("new.txt"))
        let stashes = try await git.stashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.hasSuffix(GitService.leftChangesMessage("dev")))

        try await git.switchBranch("dev")
        XCTAssertEqual(read("a.txt"), "edited on dev\n")
        XCTAssertEqual(read("new.txt"), "untracked\n")
        let remaining = try await git.stashes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testBringChangesCarriesThemAndKeepsLeftStashWaiting() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "left on dev\n")
        try await git.switchBranch("prod", leaveChangesOn: "dev")

        try write("b.txt", "brought along\n")
        try await sh(["add", "b.txt"])
        try await git.switchBranch("dev")   // bring: tree is dirty, so the dev stash is not popped over it
        let current = try await branch(git)
        XCTAssertEqual(current, "dev")
        XCTAssertEqual(read("b.txt"), "brought along\n")
        XCTAssertEqual(read("a.txt"), "base\n")
        let stashes = try await git.stashes()
        XCTAssertEqual(stashes.count, 1)
    }

    func testFailedSwitchPutsChangesBack() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "dirty\n")
        do {
            try await git.switchBranch("missing", leaveChangesOn: "dev")
            XCTFail("switch should fail")
        } catch {}
        let current = try await branch(git)
        XCTAssertEqual(current, "dev")
        XCTAssertEqual(read("a.txt"), "dirty\n")
        let stashes = try await git.stashes()
        XCTAssertTrue(stashes.isEmpty)
    }

    func testNothingToLeaveDoesNotTouchUnrelatedStash() async throws {
        let git = GitService(repo: dir)
        try write("a.txt", "manual stash\n")
        try await git.stash(message: "mine", includeUntracked: true)
        try await git.switchBranch("prod", leaveChangesOn: "dev")
        let current = try await branch(git)
        XCTAssertEqual(current, "prod")
        let stashes = try await git.stashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.hasSuffix("mine"))
    }
}
