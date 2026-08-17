import Foundation

/// Reads and writes the Cache Snapshot: the last Refresh's results — both
/// Scanned Apps and CLI Tools — persisted so the dropdown shows them
/// instantly on launch. See CONTEXT.md.
struct CacheStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL = CacheStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        return supportDirectory.appendingPathComponent("cache.json")
    }

    /// A cache file written by a version of Patchly before CLI Tools were
    /// cached (a plain `[ScannedApp]` array, not this wrapper) simply fails
    /// to decode into `CacheSnapshot` and falls through to the same empty
    /// result an unreadable/missing file already produces — no separate
    /// migration path, consistent with that existing lenient-failure
    /// behavior.
    func load() -> (apps: [ScannedApp], cliTools: [CLITool]) {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(CacheSnapshot.self, from: data)
        else {
            return (apps: [], cliTools: [])
        }
        return (apps: snapshot.apps, cliTools: snapshot.cliTools)
    }

    func save(apps: [ScannedApp], cliTools: [CLITool]) {
        let snapshot = CacheSnapshot(apps: apps, cliTools: cliTools)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct CacheSnapshot: Codable {
    let apps: [ScannedApp]
    let cliTools: [CLITool]
}
