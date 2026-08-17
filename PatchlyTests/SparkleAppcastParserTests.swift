import XCTest
@testable import Patchly

final class SparkleAppcastParserTests: XCTestCase {
    func testParsesShortVersionStringFromEnclosureAttributes() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>Version 2.0</title>
              <enclosure url="https://example.com/App-2.0.zip" sparkle:version="200" sparkle:shortVersionString="2.0" length="1000" type="application/octet-stream" />
            </item>
            <item>
              <title>Version 1.0</title>
              <enclosure url="https://example.com/App-1.0.zip" sparkle:version="100" sparkle:shortVersionString="1.0" length="1000" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(SparkleAppcastParser.latestVersion(among: items), "2.0")
    }

    func testMalformedXMLReturnsNoItemsRatherThanCrashing() {
        let xml = "<rss><channel><item><enclosure sparkle:version=\"1.0\""
        let items = SparkleAppcastParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func testPicksHighestVersionRegardlessOfDocumentOrder() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure sparkle:shortVersionString="1.5" /></item>
            <item><enclosure sparkle:shortVersionString="9.0" /></item>
            <item><enclosure sparkle:shortVersionString="10.0" /></item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(SparkleAppcastParser.latestVersion(among: items), "10.0")
    }

    func testParsesEnclosureURLAndEdSignature() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <enclosure
                url="https://example.com/App-1.2.0.zip"
                sparkle:shortVersionString="1.2.0"
                sparkle:edSignature="ify59pDIuduaZcLnLvQjGqNQIAqi4dVgeA3L/e7I7xaqn9pVdiVZH7Na3v+Gp4ElAKJfX4Pfq8cgElfXmZc4Cg=="
                length="1000"
                type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(items.first?.enclosureURL, URL(string: "https://example.com/App-1.2.0.zip"))
        XCTAssertEqual(items.first?.edSignatureBase64, "ify59pDIuduaZcLnLvQjGqNQIAqi4dVgeA3L/e7I7xaqn9pVdiVZH7Na3v+Gp4ElAKJfX4Pfq8cgElfXmZc4Cg==")
    }

    func testLatestItemPicksTheEnclosureOfTheHighestVersion() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="https://example.com/App-1.0.zip" sparkle:shortVersionString="1.0" /></item>
            <item><enclosure url="https://example.com/App-2.0.zip" sparkle:shortVersionString="2.0" /></item>
          </channel>
        </rss>
        """
        let items = SparkleAppcastParser.parse(data: Data(xml.utf8))
        let latest = SparkleAppcastParser.latestItem(among: items)
        XCTAssertEqual(latest?.enclosureURL, URL(string: "https://example.com/App-2.0.zip"))
    }
}
