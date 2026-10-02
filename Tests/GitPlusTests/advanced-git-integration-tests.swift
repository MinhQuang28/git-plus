import XCTest
@testable import GitPlus

/// Real git in temp repositories: a bare "remote", a working clone and (when needed) a second clone.
final class AdvancedGitIntegrationTests: XCTestCase {
    private var root: URL!
    private var remote: URL { root.appendingPathComponent("remote.git") }
    private var dir: URL { root.appendingPathComponent("work") }
    private var other: URL { root.appendingPathComponent("other") }
    private var git: GitService { GitService(repo: dir) }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-adv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await run(root, "init", "-q", "--bare", "-b", "main", remote.path)
        try await configure(dir, init: true)
        try write(dir, "a.txt", "one\n")
        try await run(dir, "add", ".")
        try await run(dir, "commit", "-q", "-m", "first")
        try await run(dir, "remote", "add", "origin", remote.path)
        try await run(dir, "push", "-q", "-u", "origin", "main")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func run(_ cwd: URL, _ args: String...) async throws { _ = try await ProcessRunner.run("git", args, in: cwd) }
    private func out(_ cwd: URL, _ args: String...) async throws -> String {
        try await ProcessRunner.run("git", args, in: cwd).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func configure(_ repo: URL, init: Bool = false) async throws {
        if init { try await run(repo, "init", "-q", "-b", "main") }
        try await run(repo, "config", "user.name", "T")
        try await run(repo, "config", "user.email", "t@t")
        try await run(repo, "config", "commit.gpgsign", "false")
        try await run(repo, "config", "tag.gpgsign", "false")
    }
    private func write(_ repo: URL, _ name: String, _ text: String) throws {
        try text.write(to: repo.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func read(_ name: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
    private func commit(_ repo: URL, _ name: String, _ text: String, _ message: String) async throws {
        try write(repo, name, text)
        try await run(repo, "add", "-A")
        try await run(repo, "commit", "-q", "-m", message)
    }
    /// A second clone that pushes a commit, so `work` falls behind.
    private func pushFromOther(_ name: String, _ text: String, _ message: String) async throws {
        if !FileManager.default.fileExists(atPath: other.path) {
            try await run(root, "clone", "-q", remote.path, other.path)
            try await configure(other)
        }
        try await commit(other, name, text, message)
        try await run(other, "push", "-q")
    }

    func testStatusReportsRemoteAndFetchTime() async throws {
        try await git.fetch()
        let status = try await git.status()
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertNotNil(status.lastFetched)
        XCTAssertNil(status.operation)
        let remotes = await git.remoteURLs()
        XCTAssertEqual(remotes.map(\.name), ["origin"])
    }

    func testPullRebaseWhenDivergedAndForcePushWithLease() async throws {
        try await pushFromOther("b.txt", "theirs\n", "theirs")
        try await commit(dir, "c.txt", "mine\n", "mine")
        try await git.fetch()
        var status = try await git.status()
        XCTAssertEqual(SyncSuggestion(status), .diverged(ahead: 1, behind: 1))

        do {
            try await git.pull(.fastForward)
            XCTFail("fast-forward pull should refuse diverged branches")
        } catch {
            XCTAssertEqual(GitErrorHint.classify(error.localizedDescription), .diverged)
        }
        try await git.pull(.rebase)
        status = try await git.status()
        XCTAssertEqual(status.ahead, 1)
        XCTAssertEqual(status.behind, 0)
        try await git.push(setUpstream: false)

        // Amend an already-pushed commit, then force push with lease.
        try await git.commit(summary: "mine (amended)", description: "", amend: true)
        status = try await git.status()
        XCTAssertEqual(SyncSuggestion(status), .diverged(ahead: 1, behind: 1))
        try await git.push(setUpstream: false, force: true)
        let remoteSubject = try await out(remote, "log", "-1", "--format=%s", "main")
        XCTAssertEqual(remoteSubject, "mine (amended)")
    }

    func testForceWithLeaseRefusesUnseenRemoteCommits() async throws {
        try await commit(dir, "c.txt", "mine\n", "mine")
        try await git.push(setUpstream: false)
        try await pushFromOther("b.txt", "theirs\n", "theirs")     // not fetched by `work`
        try await git.commit(summary: "rewritten", description: "", amend: true)
        // The lease compares against our stale origin/main, which the remote no longer matches.
        do {
            try await git.push(setUpstream: false, force: true)
            XCTFail("lease should protect the unseen remote commit")
        } catch {
            XCTAssertEqual(GitErrorHint.classify(error.localizedDescription), .staleLease)
        }
    }

    func testPublishUsesDefaultRemote() async throws {
        try await run(dir, "switch", "-q", "-c", "feature")
        try await commit(dir, "f.txt", "f\n", "feature")
        try await git.push(setUpstream: true)
        let status = try await git.status()
        XCTAssertEqual(status.upstream, "origin/feature")
    }

    func testTagsPushAndDelete() async throws {
        try await git.createTag("v1", at: "HEAD", message: "Release")
        var tags = try await git.tags()
        XCTAssertEqual(tags.map(\.name), ["v1"])
        try await git.pushTag("v1")
        var remoteTags = try await out(remote, "tag")
        XCTAssertEqual(remoteTags, "v1")
        try await git.deleteRemoteTag("v1")
        remoteTags = try await out(remote, "tag")
        XCTAssertEqual(remoteTags, "")
        try await git.deleteTag("v1")
        tags = try await git.tags()
        XCTAssertTrue(tags.isEmpty)
    }

    func testRemotesManagement() async throws {
        try await git.addRemote("upstream", url: "https://example.com/u/r.git")
        var remotes = try await git.remotes()
        XCTAssertEqual(remotes.map(\.name), ["origin", "upstream"])
        try await git.setRemoteURL("upstream", url: "git@example.com:u/r.git")
        remotes = try await git.remotes()
        XCTAssertEqual(remotes.last?.fetchURL, "git@example.com:u/r.git")
        try await git.removeRemote("upstream")
        remotes = try await git.remotes()
        XCTAssertEqual(remotes.map(\.name), ["origin"])
    }

    func testUndoLastCommitKeepsChangesStaged() async throws {
        try await commit(dir, "a.txt", "one\ntwo\n", "second")
        try await git.undoLastCommit()
        let log = try await git.log()
        XCTAssertEqual(log.map(\.subject), ["first"])
        let tree = try await git.workingTree()
        XCTAssertEqual(tree.staged.map(\.path), ["a.txt"])

        // Undoing the root commit leaves an unborn branch with everything staged.
        try await git.undoLastCommit()
        let empty = try await git.log()
        XCTAssertTrue(empty.isEmpty)
        let staged = try await git.workingTree()
        XCTAssertEqual(staged.staged.map(\.path), ["a.txt"])
    }

    func testDiscardAllIsUndoable() async throws {
        try write(dir, "a.txt", "changed\n")
        try write(dir, "new.txt", "new\n")
        try await git.discardAll()
        var tree = try await git.workingTree()
        XCTAssertTrue(tree.isEmpty)
        try await git.undoDiscardAll()
        tree = try await git.workingTree()
        XCTAssertEqual(Set(tree.all.map(\.path)), ["a.txt", "new.txt"])
    }

    func testGitignore() async throws {
        try write(dir, "debug.log", "x")
        try git.addToGitignore("debug.log")
        try git.addToGitignore("debug.log")   // no duplicates
        XCTAssertEqual(try read(".gitignore"), "debug.log\n")
        let tree = try await git.workingTree()
        XCTAssertEqual(tree.unstaged.map(\.path), [".gitignore"])
    }

    func testInteractiveRebaseSquashDropReword() async throws {
        try await commit(dir, "b.txt", "b\n", "add b")
        try await commit(dir, "b.txt", "b2\n", "tweak b")
        try await commit(dir, "c.txt", "c\n", "add c")
        try await commit(dir, "d.txt", "d\n", "add d")
        let commits = Array(try await git.log(ref: "HEAD~4..HEAD").reversed())   // oldest first
        XCTAssertEqual(commits.map(\.subject), ["add b", "tweak b", "add c", "add d"])
        let steps = [
            RebaseStep(commit: commits[0], action: .reword, message: "Add file b"),
            RebaseStep(commit: commits[1], action: .fixup),
            RebaseStep(commit: commits[3]),                       // reordered before c
            RebaseStep(commit: commits[2], action: .drop),
        ]
        XCTAssertNil(RebaseStep.problem(steps))
        try await git.rebaseInteractive(base: commits[0].parents.first, steps: steps)
        let log = try await git.log()
        XCTAssertEqual(log.map(\.subject), ["add d", "Add file b", "first"])
        XCTAssertEqual(try read("b.txt"), "b2\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("c.txt").path))
        let operation = await git.inProgressOperation()
        XCTAssertNil(operation)
    }

    func testRewordOlderCommitAndHead() async throws {
        try await commit(dir, "b.txt", "b\n", "typo mesage")
        try await commit(dir, "c.txt", "c\n", "head")
        var log = try await git.log()
        try await git.reword(log[1], message: "fixed message\n\nwith body")
        log = try await git.log()
        XCTAssertEqual(log.map(\.subject), ["head", "fixed message", "first"])
        let body = try await git.commitMessage(log[1].hash)
        XCTAssertTrue(body.contains("with body"))
        try await git.reword(log[0], message: "new head")
        log = try await git.log()
        XCTAssertEqual(log.first?.subject, "new head")
    }

    func testFileHistoryFollowsRenamesAndBlame() async throws {
        try await commit(dir, "a.txt", "one\ntwo\n", "add two")
        try await run(dir, "mv", "a.txt", "b.txt")
        try await run(dir, "commit", "-q", "-m", "rename")
        let history = try await git.fileHistory("b.txt")
        XCTAssertEqual(history.map(\.commit.subject), ["rename", "add two", "first"])
        XCTAssertEqual(history[0].file.status, "R")
        XCTAssertEqual(history[0].file.oldPath, "a.txt")
        XCTAssertEqual(history[1].file.path, "a.txt")

        let blame = try await git.blame("b.txt")
        XCTAssertEqual(blame.map(\.text), ["one", "two"])
        XCTAssertEqual(blame.map(\.summary), ["first", "add two"])
        let firstVersion = await git.blob("\(history[2].commit.hash):a.txt")
        XCTAssertEqual(firstVersion.map { String(decoding: $0, as: UTF8.self) }, "one\n")
    }

    func testMergeConflictPreviewSidesAndResolution() async throws {
        try await run(dir, "switch", "-q", "-c", "feature")
        try await commit(dir, "a.txt", "feature\n", "feature edit")
        try await commit(dir, "gone.txt", "will be edited\n", "add gone")
        try await run(dir, "switch", "-q", "main")
        try await commit(dir, "a.txt", "main\n", "main edit")
        try await commit(dir, "other.txt", "x\n", "unrelated")

        if let preview = await git.mergePreview("feature") {   // nil on git < 2.38
            XCTAssertEqual(preview, ["a.txt"])
        }
        do { try await git.merge("feature"); XCTFail("expected a conflict") } catch {}

        let op = await git.inProgressOperation()
        XCTAssertEqual(op, .merge)
        let sides = await git.conflictSides(.merge)
        XCTAssertEqual(sides.ours, "main")
        XCTAssertEqual(sides.theirs, "feature")

        var tree = try await git.workingTree()
        let file = try XCTUnwrap(tree.conflicted.first)
        XCTAssertEqual(file.conflictCode, "UU")
        XCTAssertEqual(git.conflictMarkerCount(file), 1)
        try await git.resolve(file, side: .theirs)
        XCTAssertEqual(try read("a.txt"), "feature\n")
        tree = try await git.workingTree()
        XCTAssertTrue(tree.conflicted.isEmpty)
        try await git.continueOperation(.merge)
        let after = await git.inProgressOperation()
        XCTAssertNil(after)
    }

    func testBlockLevelResolutionAndDeleteModifyConflict() async throws {
        try await commit(dir, "a.txt", "keep\n", "base")
        try await run(dir, "switch", "-q", "-c", "feature")
        try await commit(dir, "a.txt", "theirs\n", "feature edit")
        try await run(dir, "switch", "-q", "main")
        try await run(dir, "rm", "-q", "a.txt")
        try await run(dir, "commit", "-q", "-m", "delete a")
        try await commit(dir, "z.txt", "z1\n", "z main")
        try await run(dir, "switch", "-q", "feature")
        try await commit(dir, "z.txt", "z2\n", "z feature")
        try await run(dir, "switch", "-q", "main")
        do { try await git.merge("feature"); XCTFail("expected conflicts") } catch {}

        let tree = try await git.workingTree()
        let deleted = try XCTUnwrap(tree.conflicted.first { $0.path == "a.txt" })
        XCTAssertEqual(deleted.deletedSide, .ours)          // deleted on main, modified on feature
        try await git.resolve(deleted, side: .ours)          // keep the deletion
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.txt").path))

        let added = try XCTUnwrap(tree.conflicted.first { $0.path == "z.txt" })
        let segments = ConflictResolver.parse(try read("z.txt"))
        let blocks = ConflictResolver.blocks(segments)
        XCTAssertEqual(blocks.count, 1)
        try await git.saveResolution(added, text: ConflictResolver.resolve(segments, choices: [blocks[0].id: .oursThenTheirs]))
        XCTAssertEqual(try read("z.txt"), "z1\nz2\n")
        let remaining = try await git.workingTree()
        XCTAssertTrue(remaining.conflicted.isEmpty)
    }

    func testRebaseConflictSidesAreSwapped() async throws {
        try await run(dir, "switch", "-q", "-c", "feature")
        try await commit(dir, "a.txt", "feature\n", "feature edit")
        try await run(dir, "switch", "-q", "main")
        try await commit(dir, "a.txt", "main\n", "main edit")
        try await run(dir, "switch", "-q", "feature")
        do { try await git.rebase(onto: "main"); XCTFail("expected a conflict") } catch {}
        let sides = await git.conflictSides(.rebase)
        XCTAssertEqual(sides.ours, "main")       // during a rebase "ours" is the branch being rebased onto
        XCTAssertEqual(sides.theirs, "feature")
        try await git.abortOperation(.rebase)
    }

    func testSearchMatchesMessageOrAuthor() async throws {
        try await run(dir, "-c", "user.name=Alice", "commit", "-q", "--allow-empty", "-m", "by alice")
        try await commit(dir, "b.txt", "b\n", "mentions alice in text")
        try await commit(dir, "c.txt", "c\n", "unrelated")
        let hits = try await git.search(HistoryQuery(parsing: "alice"))
        XCTAssertEqual(Set(hits.map(\.subject)), ["by alice", "mentions alice in text"])
        let byPath = try await git.search(HistoryQuery(parsing: "path:c.txt"))
        XCTAssertEqual(byPath.map(\.subject), ["unrelated"])
        let page = try await git.log(limit: 2, skip: 1)
        XCTAssertEqual(page.map(\.subject), ["mentions alice in text", "by alice"])
    }

    func testCloneAndInit() async throws {
        let cloned = root.appendingPathComponent("cloned")
        try await GitService.clone(remote.path, into: cloned)
        XCTAssertTrue(GitService.isRepository(cloned))
        let fresh = root.appendingPathComponent("fresh/nested")
        try await GitService.initRepository(at: fresh)
        XCTAssertTrue(GitService.isRepository(fresh))
    }
}
