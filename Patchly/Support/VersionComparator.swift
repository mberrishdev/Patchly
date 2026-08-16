import Foundation

/// Dot-separated numeric version comparison — never string equality, since
/// "10" must sort after "9". See CONTEXT.md.
enum VersionComparator {
    static func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedDescending
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = numericComponents(of: lhs)
        let rhsComponents = numericComponents(of: rhs)
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<count {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left != right {
                return left < right ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func numericComponents(of version: String) -> [Int] {
        version.split(separator: ".").map { component in
            Int(component.filter(\.isNumber)) ?? 0
        }
    }
}
