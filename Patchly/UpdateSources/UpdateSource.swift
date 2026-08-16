import Foundation

struct UpdateCheckResult: Sendable {
    let status: UpdateStatus
}

/// One of the three Update Sources from CONTEXT.md. Each implementation is
/// independently testable and keyed by `DiscoveredApp.bundlePath`.
protocol UpdateSource: Sendable {
    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult]
}
