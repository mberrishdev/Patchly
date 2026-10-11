import XCTest
@testable import Patchly

final class UsageOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testMostUsedSortsByUseCountThenMostRecent() {
        let apps = [
            app("Rare", useCount: 2, lastUsed: now),
            app("Daily", useCount: 345, lastUsed: now.addingTimeInterval(-60)),
            app("Weekly", useCount: 13, lastUsed: now.addingTimeInterval(-86_400)),
            app("AlsoWeekly", useCount: 13, lastUsed: now),
        ]

        XCTAssertEqual(UsageOrder.mostUsed.sorted(apps).map(\.name), ["Daily", "AlsoWeekly", "Weekly", "Rare"])
    }

    func testLeastUsedPutsAppsWithNoRecordFirst() {
        let apps = [
            app("Daily", useCount: 345, lastUsed: now),
            app("NeverRecorded", useCount: nil, lastUsed: nil),
            app("OpenedOnce", useCount: 1, lastUsed: now.addingTimeInterval(-90 * 86_400)),
        ]

        XCTAssertEqual(UsageOrder.leastUsed.sorted(apps).map(\.name), ["NeverRecorded", "OpenedOnce", "Daily"])
    }

    func testLargestSortsBySizeWithUnsizedLast() {
        let apps = [
            app("Small", size: 12_000_000),
            app("Unsized", size: nil),
            app("Huge", size: 5_900_000_000),
        ]

        XCTAssertEqual(UsageOrder.largest.sorted(apps).map(\.name), ["Huge", "Small", "Unsized"])
    }

    func testTiesFallBackToName() {
        let apps = [app("Beta"), app("alpha"), app("Gamma")]

        XCTAssertEqual(UsageOrder.mostUsed.sorted(apps).map(\.name), ["alpha", "Beta", "Gamma"])
    }

    private func app(_ name: String, useCount: Int? = nil, lastUsed: Date? = nil, size: Int64? = nil) -> ScannedApp {
        ScannedApp(
            id: name,
            name: name,
            bundlePath: "/Applications/\(name).app",
            bundleIdentifier: nil,
            installedVersion: "1.0",
            source: .unknown,
            updateStatus: .unknownNoSource,
            lastUsedDate: lastUsed,
            useCount: useCount,
            sizeInBytes: size
        )
    }
}
