import Foundation

/// A Homebrew-installed developer CLI tool (a formula, e.g. ripgrep, jq),
/// discovered via `brew list --formula --versions` rather than a fixed name
/// list or directory scan — Homebrew already enumerates everything it
/// installed, with no need to probe individual binaries or resolve
/// symlinks. Always attributed to the Homebrew Formula Source; there is no
/// unattributed state the way there was before this was Homebrew-only. A
/// wholly separate concept from `ScannedApp`. See CONTEXT.md ("CLI Tool").
struct CLITool: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let version: String
    var source: CLIToolSource = .none
    var updateStatus: UpdateStatus = .unknownNoSource
    var updateAction: UpdateAction? = nil
    var lastCheckedAt: Date? = nil
}
