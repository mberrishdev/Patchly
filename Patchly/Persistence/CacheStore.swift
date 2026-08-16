import Foundation

/// Reads and writes the Cache Snapshot: the last Refresh's results, persisted so
/// the dropdown shows them instantly on launch. See CONTEXT.md.
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

    func load() -> [ScannedApp] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ScannedApp].self, from: data)) ?? []
    }

    func save(_ apps: [ScannedApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
