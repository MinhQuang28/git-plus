import XCTest
@testable import GitPlus

final class ProcessRunnerTests: XCTestCase {
    func testCapturesLargeOutput() async throws {
        // ~1 MB of stdout must be fully drained without blocking.
        let out = try await ProcessRunner.run("/bin/sh", ["-c", "yes 0123456789abcdef | head -c 1048576"])
        XCTAssertEqual(out.utf8.count, 1_048_576)
    }

    func testNonZeroExitThrowsWithStderr() async {
        do {
            _ = try await ProcessRunner.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
            XCTFail("expected failure")
        } catch let error as CommandError {
            XCTAssertEqual(error.status, 3)
            XCTAssertTrue(error.stderr.contains("boom"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCancellationTerminatesProcess() async {
        let start = Date()
        let task = Task { try await ProcessRunner.run("/bin/sleep", ["5"]) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.result
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2, "cancel should kill the child instead of waiting for it")
        if case .success = result { XCTFail("expected cancellation") }
    }
}
