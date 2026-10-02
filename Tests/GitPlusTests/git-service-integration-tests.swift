import XCTest
@testable import GitPlus

/// Runs the real `git` CLI against a throwaway repository.
final class GitServiceIntegrationTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gitplus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func sh(_ args: [String], in dir: URL) async throws {
        _ = try await ProcessRunner.run("git", ["-c", "user.name=T", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args, in: dir)
    }

    private func makeRepo(_ name: String) async throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await sh(["init", "-q", "-b", "main"], in: dir)
        try await sh(["remote", "add", "origin", "git@gitlab.com:team/\(name).git"], in: dir)
        return dir
    }

    func testLogDiffAndRange() async throws {
        let dir = try await makeRepo("app")
        try "one\ntwo\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await sh(["add", "."], in: dir)
        try await sh(["commit", "-q", "-m", "first"], in: dir)
        try "one\nTWO\nthree\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await sh(["commit", "-qam", "second"], in: dir)

        let git = GitService(repo: dir)
        let commits = try await git.log()
        XCTAssertEqual(commits.map(\.subject), ["second", "first"])
        XCTAssertTrue(commits[1].parents.isEmpty)

        // Root commit diffs against the empty tree.
        let rootFiles = try await git.changedFiles(.commit(commits[1]))
        XCTAssertEqual(rootFiles.map(\.status), ["A"])

        let files = try await git.changedFiles(.commit(commits[0]))
        XCTAssertEqual(files.first?.additions, 2)
        XCTAssertEqual(files.first?.deletions, 1)
        let raw = try await git.diff(.commit(commits[0]), file: files[0])
        XCTAssertTrue(DiffParser.parse(raw).lines.contains { $0.kind == .added && $0.text == "TWO" })

        let range = try XCTUnwrap(DiffTarget.range(commits))
        XCTAssertTrue(range.isRange)
        let rangeFiles = try await git.changedFiles(range)
        XCTAssertEqual(rangeFiles.first?.additions, 3)

        let searched = try await git.log(search: "SECOND")
        XCTAssertEqual(searched.count, 1)

        let status = try await git.status()
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.remote?.provider, .gitlab)
    }

    func testEmptyRepoLogIsEmpty() async throws {
        let dir = try await makeRepo("empty")
        let commits = try await GitService(repo: dir).log()
        XCTAssertTrue(commits.isEmpty)
    }

    @MainActor
    func testStoreScansAndAutoGroups() async throws {
        _ = try await makeRepo("svc-a")
        _ = try await makeRepo("svc-b")
        let store = WorkspaceStore(fileURL: root.appendingPathComponent("ws.json"))
        await store.add(folders: [root], to: nil)
        XCTAssertEqual(store.repos(in: nil).count, 2)

        await store.autoGroupByRemote()
        XCTAssertEqual(store.groups.map(\.name), ["gitlab.com/team"])
        let groupID = try XCTUnwrap(store.groups.first?.id)
        XCTAssertEqual(store.repos(in: groupID).count, 2)
        XCTAssertEqual(store.repos(in: nil).count, 0)   // cached membership refreshed after regrouping

        // Only open repositories get the Changes list from the shared status refresh.
        let first = try XCTUnwrap(store.repos(in: groupID).first)
        try "x".write(to: first.url.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        await store.refreshStatus([first.id])
        XCTAssertNil(store.trees[first.id])
        store.setOpen(first.id, true)
        await store.refreshStatus([first.id])
        XCTAssertEqual(store.trees[first.id]?.unstaged.map(\.path), ["new.txt"])
        XCTAssertEqual(store.statuses[first.id]?.changedFiles, 1)
        store.setOpen(first.id, false)
        XCTAssertNil(store.trees[first.id])

        // Persisted and reloaded.
        let reloaded = WorkspaceStore(fileURL: root.appendingPathComponent("ws.json"))
        XCTAssertEqual(reloaded.repos(in: groupID).count, 2)

        store.deleteGroup(groupID)
        XCTAssertEqual(store.repos(in: nil).count, 2)
    }
}
