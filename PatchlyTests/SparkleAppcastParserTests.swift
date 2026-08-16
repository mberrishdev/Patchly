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
}
