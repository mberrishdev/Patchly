import Foundation

/// Detects a fixed list of common developer CLI tools by resolving each name
/// against common install directories directly (never inherited `$PATH` — see
/// `ExecutableLocator`) and running `<path> --version`. Purely local and
/// read-only, so it's cheap to run as part of a Refresh. A tool that can't be
/// resolved, or resolves but fails to run/report a version, is simply
/// omitted — absence is normal here, never an error and never a status. See
/// CONTEXT.md ("CLI Tool").
actor CLIToolScanner {
    static let knownToolNames = [
        "git", "node", "npm", "npx", "python3", "pip3", "ruby", "gem", "go",
        "cargo", "rustc", "docker", "kubectl", "gh", "java", "swift", "php",
        "terraform", "aws", "gcloud", "psql", "redis-cli", "code", "copilot", "claude"
    ]

    private let processRunner: ProcessRunning
    private let toolNames: [String]
    private let directories: [URL]

    init(
        processRunner: ProcessRunning = ProcessRunner(),
        toolNames: [String] = CLIToolScanner.knownToolNames,
        directories: [URL] = ExecutableLocator.commonToolDirectories()
    ) {
        self.processRunner = processRunner
        self.toolNames = toolNames
        self.directories = directories
    }

    func scanInstalledTools() async -> [CLITool] {
        let directories = self.directories
        let processRunner = self.processRunner

        let tools = await withTaskGroup(of: CLITool?.self) { group in
            for name in toolNames {
                group.addTask {
                    await Self.resolveTool(named: name, in: directories, processRunner: processRunner)
                }
            }
            var results: [CLITool] = []
            for await tool in group {
                if let tool { results.append(tool) }
            }
            return results
        }
        return tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func resolveTool(named name: String, in directories: [URL], processRunner: ProcessRunning) async -> CLITool? {
        guard let path = ExecutableLocator.locateTool(named: name, in: directories) else { return nil }
        guard let result = try? await processRunner.run(executablePath: path, arguments: ["--version"], timeout: 5),
              result.succeeded,
              let firstLine = firstLine(of: result.standardOutput),
              !firstLine.isEmpty
        else { return nil }
        return CLITool(name: name, executablePath: path, version: firstLine)
    }

    static func firstLine(of output: String) -> String? {
        output
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
