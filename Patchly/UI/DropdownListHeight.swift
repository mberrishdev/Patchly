import CoreGraphics

/// `maxHeight` alone gives ScrollView no reliable intrinsic size in a
/// MenuBarExtra `.window` popover, and it can collapse to zero height.
/// Both dropdown lists compute an explicit height from their row count
/// instead, floored to a whole number of rows — a partial row peeking at
/// the clipped edge reads as if the footer below is covering it.
enum DropdownListHeight {
    static let estimatedRowHeight: CGFloat = 44
    static let estimatedSectionHeaderHeight: CGFloat = 22
    static let maxHeight: CGFloat = 420

    static func height(rowCount: Int, sectionHeaderCount: Int = 0) -> CGFloat {
        let contentHeight = CGFloat(rowCount) * estimatedRowHeight
            + CGFloat(sectionHeaderCount) * estimatedSectionHeaderHeight
        guard contentHeight > maxHeight else {
            return max(contentHeight, estimatedRowHeight)
        }
        return (maxHeight / estimatedRowHeight).rounded(.down) * estimatedRowHeight
    }
}
