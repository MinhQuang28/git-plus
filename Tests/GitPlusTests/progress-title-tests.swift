import XCTest
@testable import GitPlus

final class ProgressTitleTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(WorkspaceStore.progressTitle("push"), "Pushing…")
        XCTAssertEqual(WorkspaceStore.progressTitle("force push"), "Force pushing…")
        XCTAssertEqual(WorkspaceStore.progressTitle("commit"), "Committing…")
        XCTAssertEqual(WorkspaceStore.progressTitle("stage lines"), "Staging lines…")
        XCTAssertEqual(WorkspaceStore.progressTitle("checkout remote branch"), "Checking out remote branch…")
        XCTAssertEqual(WorkspaceStore.progressTitle("pull (rebase)"), "Pulling (rebase)…")
    }
}

final class UITextScaleTests: XCTestCase {
    func testStepping() {
        XCTAssertEqual(UITextScale.step(from: 1.0, by: 1), .large)
        XCTAssertEqual(UITextScale.step(from: 1.0, by: -1), .small)
        XCTAssertEqual(UITextScale.step(from: 1.4, by: 1), .largest)    // clamps at the ends
        XCTAssertEqual(UITextScale.step(from: 0.9, by: -1), .small)
        XCTAssertEqual(UITextScale.step(from: 1.05, by: 1), .larger)    // unknown stored value snaps up first
    }
}
