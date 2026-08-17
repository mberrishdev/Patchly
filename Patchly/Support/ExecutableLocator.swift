import Foundation

/// Resolves `brew`/`mas` by known install prefixes rather than inherited `$PATH` —
/// GUI apps launched via LaunchServices don't get the user's shell rc files.
enum ExecutableLocator {
    static func locateBrew() -> String? {
        locate(candidatePaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    }

    static func locateMas() -> String? {
        locate(candidatePaths: ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"])
    }

    /// Common install directories for developer CLI tools, checked directly
    /// rather than trusting inherited `$PATH` — same reasoning as `brew`/`mas`
    /// above. Order is the search order: first directory containing the tool
    /// name wins.
    static func commonToolDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fixedPaths = [
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }

        let userPaths = [".cargo/bin", "go/bin", ".local/bin"]
            .map { home.appendingPathComponent($0, isDirectory: true) }

        return fixedPaths + userPaths
    }

    /// Resolves a tool name (e.g. "node") to its full path by checking
    /// `directories` in order — first match wins. A tool that isn't found in
    /// any of them simply returns `nil`, not an error.
    static func locateTool(named name: String, in directories: [URL] = commonToolDirectories()) -> String? {
        let fileManager = FileManager.default
        for directory in directories {
            let candidate = directory.appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func locate(candidatePaths: [String]) -> String? {
        let fileManager = FileManager.default
        return candidatePaths.first { fileManager.isExecutableFile(atPath: $0) }
    }
}
