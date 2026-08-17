import XCTest
@testable import Patchly

final class VSCodeUpdateCheckerTests: XCTestCase {
    func testParseCommitFromRealProductJSONShape() throws {
        let json = """
        { "commit": "fc3def6774c76082adf699d366f31a557ce5573f", "version": "1.128.0" }
        """
        let commit = try VSCodeUpdateChecker.parseCommit(from: Data(json.utf8))
        XCTAssertEqual(commit, "fc3def6774c76082adf699d366f31a557ce5573f")
    }

    func testParseLatestVersionFromRealUpdateResponseShape() throws {
        let json = """
        {
          "url": "https://vscode.download.prss.microsoft.com/dbazure/download/stable/abc/VSCode-darwin-arm64.zip",
          "name": "1.133.0",
          "version": "abc",
          "productVersion": "1.133.0",
          "hash": "def",
          "timestamp": 1786487146992,
          "sha256hash": "ghi",
          "supportsFastUpdate": true
        }
        """
        let version = try VSCodeUpdateChecker.parseLatestVersion(from: Data(json.utf8))
        XCTAssertEqual(version, "1.133.0")
    }

    func testUpdateURLIncludesCommitAndDarwinARM64Platform() {
        let url = VSCodeUpdateChecker.updateURL(commit: "abc123")
        XCTAssertEqual(url?.absoluteString, "https://update.code.visualstudio.com/api/update/darwin-arm64/stable/abc123")
    }

    func testReadCommitFromMissingProductJSONReturnsNil() {
        XCTAssertNil(VSCodeUpdateChecker.readCommit(bundlePath: "/nonexistent/path"))
    }

    func testCheckUpdateReturnsUpToDateOn204() async {
        let session = StubURLProtocol.makeSession { _ in StubURLProtocol.Stub(data: Data(), statusCode: 204) }
        let checker = VSCodeUpdateChecker(session: session)
        let bundlePath = try! makeBundle(commit: "abc123")

        let result = await checker.checkUpdate(installedVersion: "1.128.0", bundlePath: bundlePath)

        XCTAssertEqual(result.status, .upToDate)
    }

    func testCheckUpdateReturnsUpdateAvailableWithLaunchAppAction() async throws {
        let responseJSON = """
        { "productVersion": "1.133.0" }
        """
        let session = StubURLProtocol.makeSession { _ in
            StubURLProtocol.Stub(data: Data(responseJSON.utf8), statusCode: 200)
        }
        let checker = VSCodeUpdateChecker(session: session)
        let bundlePath = try makeBundle(commit: "abc123")

        let result = await checker.checkUpdate(installedVersion: "1.128.0", bundlePath: bundlePath)

        guard case .updateAvailable(let latest) = result.status else {
            return XCTFail("Expected updateAvailable status")
        }
        XCTAssertEqual(latest, "1.133.0")
        XCTAssertEqual(result.action, .launchApp)
    }

    func testCheckUpdateReturnsCheckFailedWhenProductJSONMissing() async {
        let session = StubURLProtocol.makeSession { _ in StubURLProtocol.Stub(data: Data(), statusCode: 204) }
        let checker = VSCodeUpdateChecker(session: session)

        let result = await checker.checkUpdate(installedVersion: "1.128.0", bundlePath: "/nonexistent/path")

        guard case .checkFailed = result.status else {
            return XCTFail("Expected checkFailed status")
        }
    }

    // MARK: - Helpers

    private func makeBundle(commit: String) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchlyVSCodeUpdateCheckerTests-\(UUID().uuidString)", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Contents/Resources/app", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        let productJSON = resourcesDirectory.appendingPathComponent("product.json")
        try Data("{ \"commit\": \"\(commit)\" }".utf8).write(to: productJSON)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.path
    }
}

/// Intercepts every request on sessions built via `makeSession(handler:)` and
/// returns a canned response, so a network-backed checker can be tested
/// without a real network call.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let data: Data
        let statusCode: Int
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Stub)?

    static func makeSession(handler: @escaping (URLRequest) -> Stub) -> URLSession {
        Self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.handler?(request) ?? Stub(data: Data(), statusCode: 500)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
