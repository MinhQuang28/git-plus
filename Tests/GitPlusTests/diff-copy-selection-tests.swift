import XCTest
@testable import GitPlus

/// Copying a drag selection out of the diff: code only, no markers or hunk headers.
final class DiffCopySelectionTests: XCTestCase {
    private let diff = """
    @@ -1,3 +1,3 @@
     import A
    -let x = 1
    +let x = 2
     print(x)
    """

    func testUnifiedCopyKeepsCodeAndDropsHunkHeaders() {
        let lines = DiffParser.parse(diff).lines
        let all = lines.first!.id...lines.last!.id
        XCTAssertEqual(DiffCopySelection.text(lines, in: all), "import A\nlet x = 1\nlet x = 2\nprint(x)")
        let added = lines.first { $0.kind == .added }!.id
        XCTAssertEqual(DiffCopySelection.text(lines, in: added...added), "let x = 2")
    }

    func testSplitCopyTakesOneColumn() {
        let lines = DiffParser.parse(diff).lines
        let rows = SplitDiffBuilder.rows(lines)
        let all = rows.first!.id...rows.last!.id
        XCTAssertEqual(DiffCopySelection.text(rows, in: all, side: .left), "import A\nlet x = 1\nprint(x)")
        XCTAssertEqual(DiffCopySelection.text(rows, in: all, side: .right), "import A\nlet x = 2\nprint(x)")
    }

    func testRangeIsOrderIndependent() {
        XCTAssertEqual(DiffCopySelection(anchor: 9, head: 3).range, 3...9)
    }
}
