import Foundation

/// electron-builder's `latest-mac[-arm64].yml` — published by both the
/// `generic` provider (served directly at that URL) and the `github`
/// provider (attached as a release asset alongside the actual update
/// archive). `path` and `sha512` are what let `ElectronDirectInstaller`
/// verify a download's integrity; either can be absent on an older
/// electron-builder version or a hand-rolled feed, in which case Patchly
/// can't verify a download safely and falls back to `.launchApp`. See
/// CONTEXT.md.
struct ElectronUpdateManifest: Sendable, Hashable {
    let version: String
    let path: String?
    let sha512: String?
}

enum ElectronUpdateManifestParser {
    static func parse(_ text: String) -> ElectronUpdateManifest? {
        guard let version = topLevelValue(for: "version", in: text) else { return nil }

        // Prefer an arm64-named entry from the `files:` list when one
        // exists. Real-world case this guards against: fetching
        // `latest-mac-arm64.yml` can fail for reasons unrelated to whether
        // an arm64 build exists (seen live: an S3-hosted generic feed
        // returning AccessDenied for that specific key while serving the
        // combined `latest-mac.yml` fine) — and that combined manifest's
        // *top-level* `path`/`sha512` isn't reliably the arm64 build, just
        // whichever electron-builder listed first. Pairing the wrong path
        // with the wrong sha512 wouldn't install the wrong thing (the
        // checksum would just never match), but it would guarantee Check
        // Failed on every attempt for an app that actually does publish a
        // verifiable arm64 build.
        if let arm64File = arm64File(in: text) {
            return ElectronUpdateManifest(version: version, path: arm64File.url, sha512: arm64File.sha512)
        }

        return ElectronUpdateManifest(
            version: version,
            path: topLevelValue(for: "path", in: text),
            sha512: topLevelValue(for: "sha512", in: text)
        )
    }

    /// Only matches unindented (column-0) lines, so a `sha512:`/`path:`
    /// nested inside the indented `files:` list is never mistaken for the
    /// top-level one — electron-builder always emits top-level keys
    /// unindented and list-item properties indented under `files:`.
    private static func topLevelValue(for key: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            let value = trimmed.dropFirst("\(key):".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Parses the indented `files:` list (`- url: ...` starting each entry,
    /// a `sha512:` line belonging to whichever entry most recently started)
    /// and returns the first entry whose filename looks arm64-specific.
    private static func arm64File(in text: String) -> (url: String, sha512: String)? {
        var entries: [(url: String, sha512: String?)] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.hasPrefix(" ") || line.hasPrefix("\t") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("- url:") {
                let url = trimmed.dropFirst("- url:".count).trimmingCharacters(in: .whitespaces)
                entries.append((url: url, sha512: nil))
            } else if trimmed.hasPrefix("sha512:"), !entries.isEmpty {
                let sha512 = trimmed.dropFirst("sha512:".count).trimmingCharacters(in: .whitespaces)
                entries[entries.count - 1].sha512 = sha512
            }
        }

        for entry in entries {
            if let sha512 = entry.sha512, entry.url.lowercased().contains("arm64") {
                return (entry.url, sha512)
            }
        }
        return nil
    }
}
