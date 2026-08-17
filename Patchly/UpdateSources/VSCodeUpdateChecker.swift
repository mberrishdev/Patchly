import Foundation

/// Checks Visual Studio Code's own update API. VS Code ships a custom
/// updater rather than electron-builder's, so it publishes no
/// `app-update.yml` for the Electron Source to find, and no `SUFeedURL`
/// either — this is the one thing Patchly can check instead. The API is
/// keyed by build commit (not version): read from the app's own
/// `product.json`, then queried against the same endpoint VS Code's own
/// updater calls. A 204 response means the given commit is already latest;
/// a 200 with a JSON body means it isn't, and the body names the real
/// latest version. See CONTEXT.md ("Custom App Source").
struct VSCodeUpdateChecker: CustomAppChecker {
    let bundleIdentifier = "com.microsoft.VSCode"

    private let session: URLSession

    init(session: URLSession = VSCodeUpdateChecker.makeSession()) {
        self.session = session
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    func checkUpdate(installedVersion: String, bundlePath: String) async -> UpdateCheckResult {
        guard let commit = Self.readCommit(bundlePath: bundlePath) else {
            return UpdateCheckResult(status: .checkFailed(reason: "Could not read VS Code's product.json"))
        }
        guard let url = Self.updateURL(commit: commit) else {
            return UpdateCheckResult(status: .checkFailed(reason: "Invalid VS Code update URL"))
        }

        do {
            let (data, response) = try await session.data(from: url)
            // Empty body, not an error — the given commit is already the
            // latest build, so there's nothing to parse.
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                return UpdateCheckResult(status: .upToDate)
            }
            guard let latest = try Self.parseLatestVersion(from: data) else {
                return UpdateCheckResult(status: .checkFailed(reason: "No version in VS Code update response"))
            }
            return UpdateCheckResult(status: .updateAvailable(latestVersion: latest), action: .launchApp)
        } catch {
            return UpdateCheckResult(status: .checkFailed(reason: error.localizedDescription))
        }
    }

    static func updateURL(commit: String) -> URL? {
        URL(string: "https://update.code.visualstudio.com/api/update/darwin-arm64/stable/\(commit)")
    }

    static func readCommit(bundlePath: String) -> String? {
        let productJSONPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources/app/product.json")
        guard let data = FileManager.default.contents(atPath: productJSONPath) else { return nil }
        return try? parseCommit(from: data)
    }

    static func parseCommit(from data: Data) throws -> String? {
        struct ProductJSON: Decodable { let commit: String? }
        return try JSONDecoder().decode(ProductJSON.self, from: data).commit
    }

    static func parseLatestVersion(from data: Data) throws -> String? {
        struct UpdateResponse: Decodable { let productVersion: String? }
        return try JSONDecoder().decode(UpdateResponse.self, from: data).productVersion
    }
}
