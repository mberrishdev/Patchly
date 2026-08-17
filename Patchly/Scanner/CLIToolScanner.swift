import Foundation

/// Discovers CLI Tools via a single `brew list --formula --versions` call —
/// Homebrew already enumerates every formula it installed and its version,
/// so there's no directory scan, no per-binary `--version` probing, and no
/// symlink resolution needed to find them. Purely local and read-only. No
/// Homebrew installed, or the call failing, simply means no CLI Tools —
/// never an error and never a status. See CONTEXT.md ("CLI Tool").
actor CLIToolScanner {
    private let processRunner: ProcessRunning
    private let brewPath: String?

    init(
        processRunner: ProcessRunning = ProcessRunner(),
        brewPath: String? = ExecutableLocator.locateBrew()
    ) {
        self.processRunner = processRunner
        self.brewPath = brewPath
    }

    func scanInstalledTools() async -> [CLITool] {
        guard let brewPath else { return [] }
        guard let result = try? await processRunner.run(
            executablePath: brewPath,
            arguments: ["list", "--formula", "--versions"],
            timeout: 15
        ), result.succeeded else { return [] }

        return Self.parse(result.standardOutput)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Each line is `<formula> <version> [<version>...]` (more than one
    /// version when multiple are installed side-by-side); the last one
    /// listed is what `brew link` currently points at.
    static func parse(_ output: String) -> [CLITool] {
        var tools: [CLITool] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard let name = parts.first, let latest = parts.last, parts.count >= 2 else { continue }
            tools.append(CLITool(name: String(name), version: String(latest)))
        }
        return tools
    }
}
