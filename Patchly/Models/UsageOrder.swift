import Foundation

/// How the Usage view orders Scanned Apps. An app with no Use Count counts
/// as zero opens, and one with no Last Used Date sorts as the least recently
/// used — Spotlight's absence of a record is the closest thing to "unused"
/// Patchly can see. An app that's Open Now counts as used this moment, and
/// never lands among the Least Used, whatever Spotlight lacks for it.
/// See CONTEXT.md ("Usage view").
enum UsageOrder: String, CaseIterable, Identifiable, Sendable {
    case mostUsed
    case leastUsed
    case largest

    var id: Self { self }

    var title: String {
        switch self {
        case .mostUsed: "Most Used"
        case .leastUsed: "Least Used"
        case .largest: "Largest"
        }
    }

    func sorted(_ apps: [ScannedApp], runningBundlePaths: Set<String> = [], now: Date = Date()) -> [ScannedApp] {
        func lastUsed(_ app: ScannedApp) -> Date {
            runningBundlePaths.contains(app.bundlePath) ? now : (app.lastUsedDate ?? .distantPast)
        }
        return apps.sorted { lhs, rhs in
            switch self {
            case .mostUsed:
                if lhs.opens != rhs.opens { return lhs.opens > rhs.opens }
                if lastUsed(lhs) != lastUsed(rhs) { return lastUsed(lhs) > lastUsed(rhs) }
            case .leastUsed:
                let lhsOpen = runningBundlePaths.contains(lhs.bundlePath)
                let rhsOpen = runningBundlePaths.contains(rhs.bundlePath)
                if lhsOpen != rhsOpen { return rhsOpen }
                if lhs.opens != rhs.opens { return lhs.opens < rhs.opens }
                if lastUsed(lhs) != lastUsed(rhs) { return lastUsed(lhs) < lastUsed(rhs) }
            case .largest:
                if lhs.size != rhs.size { return lhs.size > rhs.size }
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension ScannedApp {
    var opens: Int { useCount ?? 0 }
    var size: Int64 { sizeInBytes ?? -1 }
}
