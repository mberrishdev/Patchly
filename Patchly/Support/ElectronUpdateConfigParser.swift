import Foundation

/// electron-builder's auto-updater config, read from an Electron app's
/// `Contents/Resources/app-update.yml`. Only the two providers actually seen
/// in the wild by Patchly are supported — anything else is `.unsupported`
/// rather than silently ignored, so it still surfaces as Check Failed instead
/// of being indistinguishable from "not an Electron app." See CONTEXT.md.
struct ElectronUpdateConfig: Sendable, Hashable {
    enum Provider: Sendable, Hashable {
        case github(owner: String, repo: String)
        case generic(url: String)
        case unsupported(String)
    }

    let provider: Provider
}

enum ElectronUpdateConfigParser {
    /// `app-update.yml` is a small, flat YAML file (no nesting, no lists) —
    /// simple enough to parse as key/value lines without pulling in a YAML
    /// dependency, matching Patchly's zero-third-party-dependency rule.
    static func parse(_ text: String) -> ElectronUpdateConfig? {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            values[key] = unquote(rawValue)
        }

        // A missing `provider:` key means the file exists but is malformed
        // or hand-edited, not that it doesn't exist — `parse` is only ever
        // called with a file's actual contents (see `ApplicationScanner`),
        // so returning nil here would be indistinguishable from "not an
        // Electron app" and silently lose Electron Source attribution
        // instead of surfacing Check Failed like an unrecognized provider
        // value already does below.
        guard let providerName = values["provider"] else {
            return ElectronUpdateConfig(provider: .unsupported("(missing)"))
        }

        switch providerName {
        case "github":
            guard let owner = values["owner"], let repo = values["repo"] else {
                return ElectronUpdateConfig(provider: .unsupported(providerName))
            }
            return ElectronUpdateConfig(provider: .github(owner: owner, repo: repo))
        case "generic":
            guard let url = values["url"] else {
                return ElectronUpdateConfig(provider: .unsupported(providerName))
            }
            return ElectronUpdateConfig(provider: .generic(url: url))
        default:
            return ElectronUpdateConfig(provider: .unsupported(providerName))
        }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
