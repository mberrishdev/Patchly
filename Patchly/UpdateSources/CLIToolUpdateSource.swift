import Foundation

/// The Homebrew Formula Source's Update Status check (see CONTEXT.md).
/// Independently testable and keyed by `CLITool.name`. Reuses
/// `UpdateCheckResult` since "what status, and how to install it" doesn't
/// depend on what's being checked.
protocol CLIToolUpdateSource: Sendable {
    func checkUpdates(for tools: [CLITool]) async -> [String: UpdateCheckResult]
}
