import XCTest
@testable import Patchly

final class AppStateTests: XCTestCase {
    func testDoesNotRefreshOnWakeBeforeIntervalHasElapsed() {
        let now = Date()
        let lastRefresh = now.addingTimeInterval(-60 * 60) // 1 hour ago
        XCTAssertFalse(AppState.shouldRefreshOnWake(lastRefreshDate: lastRefresh, intervalSeconds: 24 * 60 * 60, now: now))
    }

    func testRefreshesOnWakeOnceIntervalHasElapsed() {
        let now = Date()
        let lastRefresh = now.addingTimeInterval(-25 * 60 * 60) // 25 hours ago
        XCTAssertTrue(AppState.shouldRefreshOnWake(lastRefreshDate: lastRefresh, intervalSeconds: 24 * 60 * 60, now: now))
    }

    func testRefreshesOnWakeExactlyAtTheInterval() {
        let now = Date()
        let lastRefresh = now.addingTimeInterval(-24 * 60 * 60)
        XCTAssertTrue(AppState.shouldRefreshOnWake(lastRefreshDate: lastRefresh, intervalSeconds: 24 * 60 * 60, now: now))
    }

    func testAlwaysRefreshesOnWakeWhenThereIsNoPriorRefresh() {
        XCTAssertTrue(AppState.shouldRefreshOnWake(lastRefreshDate: nil, intervalSeconds: 24 * 60 * 60, now: Date()))
    }
}
