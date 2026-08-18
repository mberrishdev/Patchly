import XCTest
@testable import Patchly

final class ProcessRunnerTests: XCTestCase {
    func testTimeoutEscalatesToSigkillRatherThanHangingForever() async throws {
        // A child that outright ignores SIGTERM used to leave `run` blocked
        // on `waitUntilExit()` forever, defeating the timeout entirely. It
        // must instead be force-killed and this call must return.
        let runner = ProcessRunner()
        let start = Date()

        await XCTAssertThrowsErrorAsync(
            try await runner.run(executablePath: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 30"], timeout: 1)
        ) { error in
            guard case ProcessRunnerError.timedOut = error else {
                return XCTFail("Expected .timedOut, got \(error)")
            }
        }

        // Bounded by the 1s timeout plus the run() implementation's 5s
        // SIGKILL grace period, with headroom for scheduling overhead —
        // nowhere near the child's 30s sleep.
        XCTAssertLessThan(Date().timeIntervalSince(start), 15)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
