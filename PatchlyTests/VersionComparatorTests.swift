import XCTest
@testable import Patchly

final class VersionComparatorTests: XCTestCase {
    func testNumericComparisonBeyondSingleDigit() {
        XCTAssertTrue(VersionComparator.isVersion("10.0", greaterThan: "9.0"))
        XCTAssertFalse(VersionComparator.isVersion("9.0", greaterThan: "10.0"))
    }

    func testEqualVersionsAreNotGreater() {
        XCTAssertFalse(VersionComparator.isVersion("1.2.3", greaterThan: "1.2.3"))
        XCTAssertEqual(VersionComparator.compare("1.2.3", "1.2.3"), .orderedSame)
    }

    func testDifferentComponentCounts() {
        XCTAssertTrue(VersionComparator.isVersion("1.2.1", greaterThan: "1.2"))
        XCTAssertFalse(VersionComparator.isVersion("1.2", greaterThan: "1.2.0"))
    }

    func testNonNumericSuffixDoesNotCrash() {
        XCTAssertEqual(VersionComparator.compare("1.2.0-beta", "1.2.0"), .orderedSame)
    }
}
