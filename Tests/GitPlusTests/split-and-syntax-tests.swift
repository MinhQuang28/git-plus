import XCTest
@testable import GitPlus

final class SplitDiffBuilderTests: XCTestCase {
    private func line(_ id: Int, _ kind: DiffLineKind) -> DiffLine {
        DiffLine(id: id, kind: kind, oldNumber: nil, newNumber: nil, text: "\(id)")
    }

    func testPairsRemovedWithAddedRuns() {
        let rows = SplitDiffBuilder.rows([
            line(0, .hunk), line(1, .context),
            line(2, .removed), line(3, .removed), line(4, .added),
            line(5, .context), line(6, .added),
        ])
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].full?.id, 0)
        XCTAssertEqual(rows[1].left?.id, 1); XCTAssertEqual(rows[1].right?.id, 1)
        XCTAssertEqual(rows[2].left?.id, 2); XCTAssertEqual(rows[2].right?.id, 4)
        XCTAssertEqual(rows[3].left?.id, 3); XCTAssertNil(rows[3].right)
        XCTAssertNil(rows[5].left); XCTAssertEqual(rows[5].right?.id, 6)
    }

    func testRemovalAfterAdditionStartsNewBlock() {
        let rows = SplitDiffBuilder.rows([line(1, .removed), line(2, .added), line(3, .removed)])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].left?.id, 3)
        XCTAssertNil(rows[1].right)
    }
}

final class SyntaxHighlighterTests: XCTestCase {
    private func kinds(_ line: String, _ lang: SyntaxLanguage, block: inout Bool) -> [SyntaxTokenKind] {
        SyntaxHighlighter(language: lang).tokenize(line, inBlockComment: &block).map(\.kind)
    }

    func testSwiftTokens() {
        var block = false
        let tokens = SyntaxHighlighter(language: .swift).tokenize(#"let x: Int = 42 // note"#, inBlockComment: &block)
        XCTAssertEqual(tokens.first, SyntaxToken(text: "let", kind: .keyword))
        XCTAssertTrue(tokens.contains(SyntaxToken(text: "Int", kind: .type)))
        XCTAssertTrue(tokens.contains(SyntaxToken(text: "42", kind: .number)))
        XCTAssertEqual(tokens.last, SyntaxToken(text: "// note", kind: .comment))
        XCTAssertEqual(tokens.map(\.text).joined(), #"let x: Int = 42 // note"#)
    }

    func testStringsWithEscapesAndBlockCommentAcrossLines() {
        var block = false
        let tokens = SyntaxHighlighter(language: .javascript).tokenize(#"s = "a\"b" /* start"#, inBlockComment: &block)
        XCTAssertTrue(tokens.contains(SyntaxToken(text: #""a\"b""#, kind: .string)))
        XCTAssertTrue(block)
        XCTAssertEqual(kinds("still comment */ return", .javascript, block: &block), [.comment, .plain, .keyword])
        XCTAssertFalse(block)
    }

    func testLanguageDetection() {
        XCTAssertNotNil(SyntaxLanguage.forPath("src/App.tsx"))
        XCTAssertNotNil(SyntaxLanguage.forPath("Dockerfile"))
        XCTAssertNil(SyntaxLanguage.forPath("image.png"))
        XCTAssertTrue(DiffHighlighter.highlight([line(1, .added)], path: "a.png").isEmpty)
        XCTAssertEqual(DiffHighlighter.highlight([line(1, .added)], path: "a.py").count, 1)
    }

    private func line(_ id: Int, _ kind: DiffLineKind) -> DiffLine {
        DiffLine(id: id, kind: kind, oldNumber: nil, newNumber: 1, text: "def f(): return 1")
    }
}
