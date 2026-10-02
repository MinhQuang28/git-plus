import XCTest
@testable import GitPlus

final class RemoteInfoTests: XCTestCase {
    func testParsesCommonRemoteForms() throws {
        let cases: [(String, String, String, String, GitProvider)] = [
            ("git@github.com:acme/api.git", "github.com", "acme", "api", .github),
            ("https://github.com/acme/api", "github.com", "acme", "api", .github),
            ("https://user:tok@gitlab.com/acme/backend/api.git", "gitlab.com", "acme/backend", "api", .gitlab),
            ("ssh://git@gitlab.example.com:2222/team/sub/svc.git", "gitlab.example.com", "team/sub", "svc", .gitlab),
            ("git@bitbucket.org:me/x.git", "bitbucket.org", "me", "x", .other),
        ]
        for (raw, host, ns, name, provider) in cases {
            let info = try XCTUnwrap(RemoteInfo.parse(raw), raw)
            XCTAssertEqual(info.host, host, raw)
            XCTAssertEqual(info.namespace, ns, raw)
            XCTAssertEqual(info.name, name, raw)
            XCTAssertEqual(info.provider, provider, raw)
        }
        XCTAssertNil(RemoteInfo.parse("/local/path/repo"))
        XCTAssertNil(RemoteInfo.parse(""))
    }

    func testWebURLs() throws {
        let gl = try XCTUnwrap(RemoteInfo.parse("git@gitlab.com:g/sub/r.git"))
        XCTAssertEqual(gl.commitURL("abc")?.absoluteString, "https://gitlab.com/g/sub/r/-/commit/abc")
        XCTAssertEqual(gl.groupKey, "gitlab.com/g/sub")
        let gh = try XCTUnwrap(RemoteInfo.parse("git@github.com:o/r.git"))
        XCTAssertEqual(gh.commitURL("abc")?.absoluteString, "https://github.com/o/r/commit/abc")
    }
}

final class GitParsersTests: XCTestCase {
    func testStatusPorcelainV2() {
        let out = """
        # branch.oid 1234
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +2 -3
        1 .M N... 100644 100644 100644 a b file.txt
        ? new.txt
        """
        let s = GitParsers.status(out)
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.upstream, "origin/main")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 3)
        XCTAssertEqual(s.changedFiles, 2)
    }

    func testChangedFilesMergesRenameAndNumstat() {
        let files = GitParsers.changedFiles(
            nameStatus: "M\tsrc/a.swift\nR087\told/b.swift\tnew/b.swift\nA\timg.png\n",
            numstat: "3\t1\tsrc/a.swift\n2\t2\t{old => new}/b.swift\n-\t-\timg.png\n"
        )
        XCTAssertEqual(files.map(\.status), ["M", "R", "A"])
        XCTAssertEqual(files[1].oldPath, "old/b.swift")
        XCTAssertEqual(files[1].path, "new/b.swift")
        XCTAssertEqual(files[0].additions, 3)
        XCTAssertEqual(files[0].deletions, 1)
        XCTAssertEqual(files[2].additions, 0)
    }

    func testDiffParserLineNumbers() {
        let raw = """
        diff --git a/f b/f
        index 1..2 100644
        --- a/f
        +++ b/f
        @@ -10,3 +10,3 @@ func x()
         keep
        -old
        +new
         tail
        """
        let (lines, truncated) = DiffParser.parse(raw)
        XCTAssertFalse(truncated)
        XCTAssertEqual(lines.map(\.kind), [.hunk, .context, .removed, .added, .context])
        XCTAssertEqual(lines[2].oldNumber, 11)
        XCTAssertEqual(lines[3].newNumber, 11)
        XCTAssertEqual(lines[4].oldNumber, 12)
        XCTAssertEqual(lines[4].newNumber, 12)
    }

    func testProviderJSONDecoding() throws {
        let gh = #"[{"number":7,"title":"Fix","author":{"login":"bob"},"headRefName":"fix","state":"OPEN","isDraft":true,"url":"https://github.com/o/r/pull/7","updatedAt":"2026-01-02T03:04:05Z"}]"#
        let ghItems = try ProviderJSON.github(Data(gh.utf8))
        XCTAssertEqual(ghItems.first?.number, 7)
        XCTAssertEqual(ghItems.first?.state, "open")
        XCTAssertEqual(ghItems.first?.isDraft, true)
        XCTAssertNotNil(ghItems.first?.updatedAt)

        let gl = #"[{"iid":3,"title":"Feat","author":{"username":"amy"},"source_branch":"feat","state":"opened","draft":false,"web_url":"https://gitlab.com/g/r/-/merge_requests/3","updated_at":"2026-01-02T03:04:05.123Z"}]"#
        let glItems = try ProviderJSON.gitlab(Data(gl.utf8))
        XCTAssertEqual(glItems.first?.number, 3)
        XCTAssertEqual(glItems.first?.author, "amy")
        XCTAssertNotNil(glItems.first?.updatedAt)
        XCTAssertEqual(try ProviderJSON.gitlab(Data("\n".utf8)).count, 0)
    }
}
