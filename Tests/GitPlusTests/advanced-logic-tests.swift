import XCTest
@testable import GitPlus

final class SyncAndErrorHintTests: XCTestCase {
    private func status(ahead: Int = 0, behind: Int = 0, upstream: String? = "origin/main", remote: Bool = true) -> RepoStatus {
        var s = RepoStatus()
        s.ahead = ahead
        s.behind = behind
        s.upstream = upstream
        s.remote = remote ? RemoteInfo.parse("git@github.com:o/r.git") : nil
        return s
    }

    func testSyncSuggestion() {
        XCTAssertEqual(SyncSuggestion(status()), .fetch)
        XCTAssertEqual(SyncSuggestion(status(ahead: 2)), .push(ahead: 2))
        XCTAssertEqual(SyncSuggestion(status(behind: 3)), .pull(behind: 3))
        XCTAssertEqual(SyncSuggestion(status(ahead: 1, behind: 1)), .diverged(ahead: 1, behind: 1))
        XCTAssertEqual(SyncSuggestion(status(upstream: nil)), .publish)
        XCTAssertEqual(SyncSuggestion(status(upstream: nil, remote: false)), .noRemote)
        XCTAssertTrue(SyncSuggestion.diverged(ahead: 1, behind: 1).needsAttention)
    }

    func testErrorHints() {
        XCTAssertEqual(GitErrorHint.classify(" ! [rejected]        main -> main (fetch first)\nerror: failed to push some refs"), .pushRejected)
        XCTAssertEqual(GitErrorHint.classify(" ! [rejected]        main -> main (stale info)"), .staleLease)
        XCTAssertEqual(GitErrorHint.classify("hint: You have divergent branches\nfatal: Not possible to fast-forward, aborting."), .diverged)
        XCTAssertEqual(GitErrorHint.classify("fatal: could not read Username for 'https://github.com': terminal prompts disabled"), .authentication)
        XCTAssertEqual(GitErrorHint.classify("error: Your local changes to the following files would be overwritten by checkout"), .localChanges)
        XCTAssertEqual(GitErrorHint.classify("fatal: Unable to create '/r/.git/index.lock': File exists."), .lockFile)
        XCTAssertEqual(GitErrorHint.classify("CONFLICT (content): Merge conflict in a.txt"), .conflicts)
        XCTAssertNil(GitErrorHint.classify("something else"))
    }
}

final class CommitGraphTests: XCTestCase {
    private func commit(_ hash: String, _ parents: [String]) -> Commit {
        Commit(hash: hash, shortHash: hash, parents: parents, author: "a", email: "a", date: .now, subject: hash, refs: [])
    }

    func testLinearHistoryUsesOneLane() {
        let rows = CommitGraph.layout([commit("c", ["b"]), commit("b", ["a"]), commit("a", [])])
        XCTAssertEqual(rows.map(\.node), [0, 0, 0])
        XCTAssertEqual(rows.map(\.width), [1, 1, 1])
        XCTAssertEqual(rows[0].top, [])
        XCTAssertEqual(rows[1].top, [GraphRow.Segment(from: 0, to: 0)])
        XCTAssertEqual(rows[2].bottom, [])
    }

    func testBranchAndMerge() {
        // m merges f into main: m -> (b, f), f -> a, b -> a
        let rows = CommitGraph.layout([commit("m", ["b", "f"]), commit("f", ["a"]), commit("b", ["a"]), commit("a", [])])
        XCTAssertTrue(rows[0].isMerge)
        XCTAssertEqual(rows[0].node, 0)
        XCTAssertEqual(Set(rows[0].bottom), [GraphRow.Segment(from: 0, to: 0), GraphRow.Segment(from: 0, to: 1)])
        XCTAssertEqual(rows[1].node, 1)                                   // f in the second lane
        XCTAssertEqual(rows[2].node, 0)                                   // b back in the first lane
        XCTAssertTrue(rows[2].bottom.contains(GraphRow.Segment(from: 1, to: 0)))   // f's lane folds into main
        XCTAssertEqual(rows[3].node, 0)
        XCTAssertEqual(rows[3].top, [GraphRow.Segment(from: 0, to: 0)])
        XCTAssertEqual(rows.map(\.width).max(), 2)
    }
}

final class SearchAndPaletteTests: XCTestCase {
    func testFuzzyMatch() {
        XCTAssertNotNil(FuzzyMatch.score("fp", "Force Push"))
        XCTAssertNil(FuzzyMatch.score("xyz", "Force Push"))
        XCTAssertGreaterThan(FuzzyMatch.score("pull", "Pull")!, FuzzyMatch.score("pull", "Open Pull Requests")!)
        XCTAssertEqual(FuzzyMatch.score("", "anything"), 0)
    }

    func testHistoryQueryParsing() {
        let q = HistoryQuery(parsing: "fix login author:minh path:src/app")
        XCTAssertEqual(q.text, "fix login")
        XCTAssertEqual(q.author, "minh")
        XCTAssertEqual(q.paths, ["src/app"])
        XCTAssertTrue(HistoryQuery(parsing: "a1b2c3d").looksLikeHash)
        XCTAssertFalse(HistoryQuery(parsing: "readme").looksLikeHash)
        XCTAssertTrue(HistoryQuery(parsing: "  ").isEmpty)
    }
}

final class ConflictResolverTests: XCTestCase {
    private let text = """
    top
    <<<<<<< HEAD
    ours 1
    ours 2
    ||||||| base
    base
    =======
    theirs
    >>>>>>> feature
    middle
    <<<<<<< HEAD
    x
    =======
    y
    >>>>>>> feature
    end

    """

    func testParseBlocks() {
        let segments = ConflictResolver.parse(text)
        let blocks = ConflictResolver.blocks(segments)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].ours, ["ours 1", "ours 2"])
        XCTAssertEqual(blocks[0].base, ["base"])
        XCTAssertEqual(blocks[0].theirs, ["theirs"])
        XCTAssertEqual(blocks[0].oursLabel, "HEAD")
        XCTAssertEqual(blocks[0].theirsLabel, "feature")
        XCTAssertNil(blocks[1].base)
    }

    func testResolveChoices() {
        let segments = ConflictResolver.parse(text)
        XCTAssertEqual(ConflictResolver.resolve(segments, choices: [0: .theirs, 1: .oursThenTheirs]), "top\ntheirs\nmiddle\nx\ny\nend\n")
        let partial = ConflictResolver.resolve(segments, choices: [0: .ours])
        XCTAssertEqual(ConflictResolver.blocks(ConflictResolver.parse(partial)).count, 1)   // unresolved block keeps its markers
        XCTAssertTrue(partial.hasPrefix("top\nours 1\nours 2\nmiddle\n<<<<<<< HEAD\n"))
    }
}

final class ExtraParserTests: XCTestCase {
    func testRemotes() {
        let out = "origin\tgit@github.com:o/r.git (fetch)\norigin\tgit@github.com:o/r-push.git (push)\nup\thttps://x/y.git (fetch)\nup\thttps://x/y.git (push)\n"
        let remotes = GitParsers.remotes(out)
        XCTAssertEqual(remotes.map(\.name), ["origin", "up"])
        XCTAssertEqual(remotes[0].fetchURL, "git@github.com:o/r.git")
        XCTAssertEqual(remotes[0].pushURL, "git@github.com:o/r-push.git")
    }

    func testTags() {
        let tags = GitParsers.tags("v1.0\u{1f}abc1234\u{1f}2024-05-01T10:00:00+02:00\u{1f}Release 1\nv0.9\u{1f}def5678\u{1f}\u{1f}\n")
        XCTAssertEqual(tags.map(\.name), ["v1.0", "v0.9"])
        XCTAssertNotNil(tags[0].date)
        XCTAssertEqual(tags[0].subject, "Release 1")
    }

    func testBlamePorcelain() {
        let sha1 = String(repeating: "a", count: 40), sha2 = String(repeating: "b", count: 40)
        let out = """
        \(sha1) 1 1 2
        author Alice
        author-time 1700000000
        summary First
        filename f
        \tline one
        \(sha1) 2 2
        \tline two
        \(sha2) 3 3 1
        author Bob
        author-time 1700000100
        summary Second
        filename f
        \tline three

        """
        let lines = GitParsers.blame(out)
        XCTAssertEqual(lines.map(\.number), [1, 2, 3])
        XCTAssertEqual(lines.map(\.author), ["Alice", "Alice", "Bob"])
        XCTAssertEqual(lines[1].summary, "First")
        XCTAssertEqual(lines[2].text, "line three")
        XCTAssertEqual(lines[2].date, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testMergedBranchFromMessage() {
        XCTAssertEqual(GitService.mergedBranch(fromMessage: "Merge branch 'feature/x' into main\n\n# Conflicts:"), "feature/x")
        XCTAssertEqual(GitService.mergedBranch(fromMessage: "Merge remote-tracking branch 'origin/dev'"), "origin/dev")
        XCTAssertNil(GitService.mergedBranch(fromMessage: "Something"))
        XCTAssertEqual(GitService.repositoryName(fromRemote: "git@github.com:acme/api.git"), "api")
        XCTAssertEqual(GitService.repositoryName(fromRemote: "/srv/git/tools.git/"), "tools")
    }

    func testRebaseValidation() {
        let c = { (h: String) in Commit(hash: h, shortHash: h, parents: [], author: "", email: "", date: .now, subject: h, refs: []) }
        XCTAssertNotNil(RebaseStep.problem([RebaseStep(commit: c("a"), action: .squash)]))
        XCTAssertNotNil(RebaseStep.problem([RebaseStep(commit: c("a"), action: .drop)]))
        XCTAssertNotNil(RebaseStep.problem([RebaseStep(commit: c("a"), action: .reword, message: " ")]))
        XCTAssertNil(RebaseStep.problem([RebaseStep(commit: c("a")), RebaseStep(commit: c("b"), action: .fixup)]))
        XCTAssertNotNil(RebaseStep.problem([RebaseStep(commit: c("a"), action: .drop), RebaseStep(commit: c("b"), action: .fixup)]))
    }
}

final class ChangeMapTests: XCTestCase {
    private func lines(_ kinds: String) -> [DiffLine] {
        kinds.enumerated().map { i, c in
            let kind: DiffLineKind = c == "+" ? .added : c == "-" ? .removed : c == "@" ? .hunk : .context
            return DiffLine(id: i, kind: kind, oldNumber: nil, newNumber: nil, text: "")
        }
    }

    func testRunsBecomeMarks() {
        let marks = ChangeMark.build(lines("@ --++ ++ -"))
        XCTAssertEqual(marks.map(\.kind), [.removed, .added, .added, .removed])
        XCTAssertEqual(marks.map(\.lineID), [2, 4, 7, 10])
        XCTAssertEqual(marks.last?.end, 1)
    }

    func testHugeDiffsAreBucketed() {
        let big = lines(String((0..<20_000).map { i -> Character in i % 3 == 0 ? "+" : i % 3 == 1 ? "-" : " " }))
        let marks = ChangeMark.build(big)
        XCTAssertLessThanOrEqual(marks.count, 300)
        XCTAssertEqual(marks.first?.kind, .mixed)
        XCTAssertTrue(ChangeMark.build([]).isEmpty)
    }
}
