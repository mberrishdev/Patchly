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

    private static func locate(candidatePaths: [String]) -> String? {
        let fileManager = FileManager.default
        return candidatePaths.first { fileManager.isExecutableFile(atPath: $0) }
    }
}
