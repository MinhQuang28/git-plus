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
    private func read(_ name: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }

    func testPorcelainParserSplitsAreas() {
        let h = "N... 100644 100644 100644 h1 h2"
        let tree = GitParsers.snapshot([
            "1 MM \(h) a.txt", "? new.txt", "2 R. \(h) R100 b.txt", "old.txt", "1 D. \(h) gone.txt",
            "u UU N... 100644 100644 100644 100644 h1 h2 h3 c.txt",
        ].joined(separator: "\0") + "\0").tree
        XCTAssertEqual(tree.staged.map(\.path), ["a.txt", "b.txt", "gone.txt"])
        XCTAssertEqual(tree.unstaged.map(\.path), ["a.txt", "new.txt"])
        XCTAssertEqual(tree.conflicted.map(\.path), ["c.txt"])
        XCTAssertEqual(tree.staged.first { $0.path == "b.txt" }?.oldPath, "old.txt")
        XCTAssertNotEqual(tree.staged[0].id, tree.unstaged[0].id)   // same path, different areas
    }

    func testStageUnstageCommitAndAmend() async throws {
        try write("a.txt", "one\ntwo\n")
        try write("new.txt", "hello\n")
        var tree = try await git.workingTree()
        XCTAssertEqual(tree.unstaged.map(\.path), ["a.txt", "new.txt"])
        let untracked = try await git.workingDiff(tree.unstaged[1])
        XCTAssertTrue(DiffParser.parse(untracked).lines.contains { $0.kind == .added && $0.text == "hello" })

        try await git.stage([tree.unstaged[0]])
        tree = try await git.workingTree()
        XCTAssertEqual(tree.staged.map(\.path), ["a.txt"])
        let stagedDiff = try await git.workingDiff(tree.staged[0])
        XCTAssertTrue(stagedDiff.contains("+two"))

        try await git.commit(summary: "two", description: "")
        tree = try await git.workingTree()
        XCTAssertEqual(tree.staged.count, 0)
        XCTAssertEqual(tree.unstaged.map(\.path), ["new.txt"])

        try await git.stageAll()
        try await git.commit(summary: "two + new", description: "body", amend: true)
        let log = try await git.log()
        XCTAssertEqual(log.map(\.subject), ["two + new", "first"])
        let last = await git.lastCommitMessage()
        XCTAssertEqual(last.description, "body")

        try write("a.txt", "changed\n")
        try await git.stageAll()
        try await git.unstageAll()
        tree = try await git.workingTree()
        XCTAssertTrue(tree.staged.isEmpty)
        try await git.discard(tree.unstaged[0])
        let empty = try await git.workingTree()
        XCTAssertTrue(empty.isEmpty)
    }

    func testLineAndHunkStaging() async throws {
        try write("a.txt", "one\ntwo\nthree\nfour\n")
        try await sh("commit", "-qam", "base")
        try write("a.txt", "ONE\ntwo\nthree\nFOUR\n")
        let file = try await git.workingTree().unstaged[0]
        let raw = try await git.workingDiff(file, context: 0)
        let lines = DiffParser.parse(raw).lines

        // Stage only the change to line 1 ("one" → "ONE").
        let pick = Set(lines.filter { ($0.kind == .removed && $0.text == "one") || ($0.kind == .added && $0.text == "ONE") }.map(\.id))
        let patch = try XCTUnwrap(PatchBuilder.patch(raw: raw, selected: pick, reverse: false))
        try await git.apply(patch: patch, cached: true, reverse: false)
        let staged = try await git.git(["show", ":a.txt"])
        XCTAssertEqual(staged, "ONE\ntwo\nthree\nfour\n")

        // Unstage it again from the staged diff (reverse, whole hunk).
        let stagedFile = try await git.workingTree().staged[0]
        let stagedRaw = try await git.workingDiff(stagedFile, context: 0)
        let hunk = try XCTUnwrap(DiffParser.parse(stagedRaw).lines.first { $0.kind == .hunk })
        let unstagePatch = try XCTUnwrap(PatchBuilder.patch(
            raw: stagedRaw, selected: PatchBuilder.changeLines(inHunk: hunk.id, raw: stagedRaw), reverse: true))
        try await git.apply(patch: unstagePatch, cached: true, reverse: true)
        let tree = try await git.workingTree()
        XCTAssertTrue(tree.staged.isEmpty)

        // Discard only the "four" → "FOUR" change in the worktree.
        let raw2 = try await git.workingDiff(tree.unstaged[0], context: 0)
        let four = Set(DiffParser.parse(raw2).lines.filter { $0.text == "four" || $0.text == "FOUR" }.map(\.id))
        let discard = try XCTUnwrap(PatchBuilder.patch(raw: raw2, selected: four, reverse: true))
        try await git.apply(patch: discard, cached: false, reverse: true)
        XCTAssertEqual(try read("a.txt"), "ONE\ntwo\nthree\nfour\n")
    }

    func testLineStagingWithDefaultContext() async throws {
        try write("a.txt", (1...12).map { "line\($0)" }.joined(separator: "\n") + "\n")
        try await sh("commit", "-qam", "base")
        try write("a.txt", (1...12).map { $0 == 2 ? "TWO" : $0 == 11 ? "ELEVEN" : "line\($0)" }.joined(separator: "\n") + "\n")
        let file = try await git.workingTree().unstaged[0]
        let raw = try await git.workingDiff(file)   // -U3: one hunk per change, each with context
        let ids = Set(DiffParser.parse(raw).lines.filter { $0.text == "line11" || $0.text == "ELEVEN" }.map(\.id))
        let patch = try XCTUnwrap(PatchBuilder.patch(raw: raw, selected: ids, reverse: false))
        try await git.apply(patch: patch, cached: true, reverse: false)
        let index = try await git.git(["show", ":a.txt"])
        XCTAssertTrue(index.contains("ELEVEN"))
        XCTAssertTrue(index.contains("line2\n"))
    }

    func testStashMergeConflictAndBranches() async throws {
        try write("a.txt", "stashed\n")
        try await git.stash(message: "wip", includeUntracked: true)
        var stashes = try await git.stashes()
        XCTAssertEqual(stashes.count, 1)
        XCTAssertTrue(stashes[0].message.contains("wip"))
        let files = try await git.changedFiles(GitService.stashTarget(stashes[0]))
        XCTAssertEqual(files.map(\.path), ["a.txt"])
        try await git.applyStash(stashes[0], pop: true)
        stashes = try await git.stashes()
        XCTAssertTrue(stashes.isEmpty)
        XCTAssertEqual(try read("a.txt"), "stashed\n")
        try await git.discard(try await git.workingTree().unstaged[0])

        // Conflicting merge → in-progress operation → resolve with "theirs" → continue.
        try await git.createBranch("feature")
        try write("a.txt", "feature\n")
        try await sh("commit", "-qam", "feature change")
        try await git.switchBranch("main")
        try write("a.txt", "main\n")
        try await sh("commit", "-qam", "main change")
        do { try await git.merge("feature"); XCTFail("expected conflict") } catch {}
        let op = await git.inProgressOperation()
        XCTAssertEqual(op, .merge)
        let status = try await git.status()
        XCTAssertEqual(status.conflicts, 1)
        let conflicted = try await git.workingTree().conflicted[0]
        try await git.resolve(conflicted, useOurs: false)
        try await git.continueOperation(.merge)
        let after = await git.inProgressOperation()
        XCTAssertNil(after)
        XCTAssertEqual(try read("a.txt"), "feature\n")

        try await git.renameBranch("feature", to: "done")
        try await git.deleteBranch("done", force: false)
        let branches = try await git.branches()
        XCTAssertEqual(branches.local, ["main"])
    }

    func testResetModesRevertTagAndCherryPick() async throws {
        try write("a.txt", "one\ntwo\n")
        try await sh("commit", "-qam", "second")
        let log = try await git.log()
        try await git.createTag("v1", at: log[1].hash, message: "release")
        let tagged = try await git.log()
        XCTAssertTrue(tagged[1].refs.contains("tag: v1"))

        try await git.revert(log[0])
        let afterRevert = try await git.log()
        XCTAssertEqual(afterRevert.first?.subject, #"Revert "second""#)

        try await git.createBranch("feature", at: log[1].hash)
        try await git.switchBranch("main")
        try await git.cherryPick(log[0].hash, onto: "feature")
        let current = try await git.branches().current
        XCTAssertEqual(current, "main")

        try await git.reset(to: log[0].hash, mode: .soft)
        var tree = try await git.workingTree()
        XCTAssertEqual(tree.staged.map(\.path), ["a.txt"])
        try await git.reset(to: log[0].hash, mode: .hard)
        tree = try await git.workingTree()
        XCTAssertTrue(tree.isEmpty)
        let head = await git.headHash()
        XCTAssertEqual(head, log[0].hash)
    }
}
