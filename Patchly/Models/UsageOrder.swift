import Foundation

/// How the Usage view orders Scanned Apps. An app with no Use Count counts
/// as zero opens, and one with no Last Used Date sorts as the least recently
/// used — Spotlight's absence of a record is the closest thing to "unused"
/// Patchly can see. See CONTEXT.md ("Usage view").
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

    func sorted(_ apps: [ScannedApp]) -> [ScannedApp] {
        apps.sorted { lhs, rhs in
            switch self {
            case .mostUsed:
                if lhs.opens != rhs.opens { return lhs.opens > rhs.opens }
                if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed > rhs.lastUsed }
            case .leastUsed:
                if lhs.opens != rhs.opens { return lhs.opens < rhs.opens }
                if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed < rhs.lastUsed }
            case .largest:
                if lhs.size != rhs.size { return lhs.size > rhs.size }
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension ScannedApp {
    var opens: Int { useCount ?? 0 }
    var lastUsed: Date { lastUsedDate ?? .distantPast }
    var size: Int64 { sizeInBytes ?? -1 }
}
