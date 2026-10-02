import XCTest
@testable import GitPlus

final class WorkingTreeAndCommitActionsTests: XCTestCase {
    private var dir: URL!
    private var git: GitService { GitService(repo: dir) }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await sh("init", "-q", "-b", "main")
        try await sh("config", "user.name", "T")
        try await sh("config", "user.email", "t@t")
        try await sh("config", "commit.gpgsign", "false")
        try write("a.txt", "one\n")
        try await sh("add", ".")
        try await sh("commit", "-q", "-m", "first")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private func sh(_ args: String...) async throws { _ = try await ProcessRunner.run("git", args, in: dir) }
    private func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testPorcelainParser() {
        let files = GitParsers.workingChanges(" M a.txt\0?? new.txt\0R  b.txt\0old.txt\0D  gone.txt\0")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.status) }),
                       ["a.txt": "M", "new.txt": "?", "b.txt": "R", "gone.txt": "D"])
        XCTAssertEqual(files.first { $0.path == "b.txt" }?.oldPath, "old.txt")
    }

    func testCommitOnlyCheckedFilesAndUntrackedDiff() async throws {
        try write("a.txt", "one\ntwo\n")
        try write("new.txt", "hello\n")
        try write("skip.txt", "later\n")
        let changes = try await git.workingChanges()
        XCTAssertEqual(changes.map(\.path), ["a.txt", "new.txt", "skip.txt"])

        let untracked = try await git.workingDiff(changes[1])
        XCTAssertTrue(DiffParser.parse(untracked).lines.contains { $0.kind == .added && $0.text == "hello" })
        let tracked = try await git.workingDiff(changes[0])
        XCTAssertTrue(DiffParser.parse(tracked).lines.contains { $0.kind == .added && $0.text == "two" })

        try await git.commit(files: Array(changes.prefix(2)), summary: "add two", description: "body")
        let remaining = try await git.workingChanges()
        XCTAssertEqual(remaining.map(\.path), ["skip.txt"])
        let message = try await git.commitMessage("HEAD")
        XCTAssertTrue(message.hasPrefix("add two\n\nbody"))
    }

    func testDiscardRestoresAndDeletesUntracked() async throws {
        try write("a.txt", "changed\n")
        try write("tmp.txt", "x\n")
        for file in try await git.workingChanges() { try await git.discard(file) }
        let after = try await git.workingChanges()
        XCTAssertTrue(after.isEmpty)
    }

    func testResetRevertTagBranchAndCherryPick() async throws {
        try write("a.txt", "one\ntwo\n")
        try await sh("commit", "-qam", "second")
        var log = try await git.log()
        XCTAssertEqual(log.count, 2)

        try await git.createTag("v1", at: log[1].hash)
        log = try await git.log()
        XCTAssertTrue(log[1].refs.contains("tag: v1"))

        try await git.revert(log[0])
        let afterRevert = try await git.log()
        XCTAssertEqual(afterRevert.first?.subject, #"Revert "second""#)

        // Branch from the first commit, then cherry-pick "second" onto it without leaving main.
        try await git.createBranch("feature", at: log[1].hash)
        try await git.switchBranch("main")
        try await git.cherryPick(log[0].hash, onto: "feature")
        let current = try await git.branches().current
        XCTAssertEqual(current, "main")
        let feature = try await git.log(ref: "feature")
        XCTAssertEqual(feature.first?.subject, "second")

        // Same parent + same second ⇒ the picked commit is byte-identical to "second",
        // so feature is fully contained in main: main is ahead by the revert only.
        let ab = await git.aheadBehind("feature")
        XCTAssertEqual(ab.ahead, 1)
        XCTAssertEqual(ab.behind, 0)

        // Mixed reset keeps the reverted content as a working-tree change.
        try await git.reset(to: log[0].hash)
        let head = await git.headHash()
        XCTAssertEqual(head, log[0].hash)
        let changed = try await git.workingChanges()
        XCTAssertEqual(changed.map(\.path), ["a.txt"])
    }
}
