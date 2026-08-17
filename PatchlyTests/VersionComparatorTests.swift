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

    func testParentheticalBuildNumberDoesNotInflateTheComponent() {
        // Real bug: Arc's appcast reports "1.160.0 (85122)" — filtering every
        // digit in "0 (85122)" used to concatenate to 085122 and badly
        // outrank a clean "0", falsely showing an update for the same version.
        XCTAssertEqual(VersionComparator.compare("1.160.0 (85122)", "1.160.0"), .orderedSame)
        XCTAssertFalse(VersionComparator.isVersion("1.160.0 (85122)", greaterThan: "1.160.0"))
    }
}
