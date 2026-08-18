import XCTest
@testable import Patchly

final class ElectronUpdateConfigParserTests: XCTestCase {
    func testParsesGitHubProvider() {
        // Captured from a real installed app's Contents/Resources/app-update.yml.
        let yaml = """
        owner: RedisInsight
        repo: RedisInsight
        provider: github
        updaterCacheDirName: redisinsight-updater
        """
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .github(owner: "RedisInsight", repo: "RedisInsight")))
    }

    func testParsesGenericProvider() {
        // Captured from a real installed app's Contents/Resources/app-update.yml.
        let yaml = """
        provider: generic
        url: https://packages.loom.com/desktop-packages/
        updaterCacheDirName: loom-updater
        """
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .generic(url: "https://packages.loom.com/desktop-packages/")))
    }

    func testUnsupportedProviderIsReportedNotDropped() {
        let yaml = """
        provider: s3
        bucket: my-bucket
        region: us-east-1
        """
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .unsupported("s3")))
    }

    func testGitHubProviderMissingOwnerOrRepoIsUnsupported() {
        let yaml = "provider: github\nrepo: SomeRepo"
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .unsupported("github")))
    }

    func testGenericProviderMissingURLIsUnsupported() {
        let yaml = "provider: generic\nchannel: latest"
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .unsupported("generic")))
    }

    func testNoProviderKeyIsUnsupportedNotNil() {
        // A missing `provider:` key means the file exists but is malformed,
        // not that there's no Electron update config at all — this must
        // still surface as Check Failed (via .unsupported), the same as an
        // unrecognized provider value, rather than silently losing Electron
        // Source attribution the way returning nil would.
        let config = ElectronUpdateConfigParser.parse("owner: SomeOrg\nrepo: SomeRepo")
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .unsupported("(missing)")))
    }

    func testQuotedValuesAreUnwrapped() {
        let yaml = "provider: generic\nurl: \"https://example.com/updates\""
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .generic(url: "https://example.com/updates")))
    }

    func testCommentsAndBlankLinesAreIgnored() {
        let yaml = """
        # electron-builder auto-update config

        provider: github
        owner: example-org

        repo: example-repo
        """
        let config = ElectronUpdateConfigParser.parse(yaml)
        XCTAssertEqual(config, ElectronUpdateConfig(provider: .github(owner: "example-org", repo: "example-repo")))
    }
}
