import Foundation

/// Measures a Scanned App's size on disk for the bundles Spotlight never
/// sized. Walking a bundle visits every file in it — seconds for a large app
/// — so this only ever runs for apps that came out of the scan without a
/// size, never for all of them. See CONTEXT.md ("App Size").
enum AppSizeCalculator {
    static func measureUnsizedApps(_ apps: [DiscoveredApp]) async -> [String: Int64] {
        let unsized = apps.filter { $0.sizeInBytes == nil }.map(\.bundlePath)
        return await withTaskGroup(of: (String, Int64?).self) { group in
            for bundlePath in unsized {
                group.addTask {
                    (bundlePath, allocatedSize(of: URL(fileURLWithPath: bundlePath)))
                }
            }
            var sizes: [String: Int64] = [:]
            for await (bundlePath, size) in group {
                sizes[bundlePath] = size
            }
            return sizes
        }
    }

    /// Allocated size rather than logical size, matching what Finder's
    /// "Size on disk" and Spotlight's `kMDItemPhysicalSize` report.
    static func allocatedSize(of bundleURL: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
