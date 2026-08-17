import Foundation

/// A detected developer CLI tool (e.g. git, node, npm), display-only: no
/// Update Source, Update Status, or Update Action apply to it — there is no
/// safe universal way to check or install updates for arbitrary CLI tools.
/// A wholly separate concept from `ScannedApp`. See CONTEXT.md ("CLI Tool").
struct CLITool: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let executablePath: String
    let version: String
}
