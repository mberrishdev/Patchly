import Foundation

struct UpdateCheckResult: Sendable {
    let status: UpdateStatus
    var action: UpdateAction? = nil
}

/// One of the Update Sources from CONTEXT.md. Each implementation is
/// independently testable and keyed by `DiscoveredApp.bundlePath`.
protocol UpdateSource: Sendable {
    func checkUpdates(for apps: [DiscoveredApp]) async -> [String: UpdateCheckResult]
}
