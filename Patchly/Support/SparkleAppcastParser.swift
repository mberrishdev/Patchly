import Foundation

struct SparkleAppcastItem: Sendable, Equatable {
    let version: String?
    let shortVersionString: String?
}

/// Parses a Sparkle appcast XML feed belonging to another app. Patchly only reads
/// these feeds — it does not use the Sparkle framework itself. See CONTEXT.md.
final class SparkleAppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var items: [SparkleAppcastItem] = []
    private var currentVersion: String?
    private var currentShortVersionString: String?
    private var currentElementText = ""
    private var isInsideItem = false

    static func parse(data: Data) -> [SparkleAppcastItem] {
        let delegate = SparkleAppcastParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        xmlParser.parse()
        return delegate.items
    }

    /// The highest version across all items, preferring `shortVersionString` over `version`.
    static func latestVersion(among items: [SparkleAppcastItem]) -> String? {
        let candidates = items.compactMap { $0.shortVersionString ?? $0.version }
        return candidates.max { VersionComparator.compare($0, $1) == .orderedAscending }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" {
            isInsideItem = true
            currentVersion = nil
            currentShortVersionString = nil
        }
        if elementName == "enclosure", isInsideItem {
            for (key, value) in attributeDict {
                if key.hasSuffix("shortVersionString") {
                    currentShortVersionString = value
                } else if key.hasSuffix("version") {
                    currentVersion = value
                }
            }
        }
        currentElementText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if isInsideItem {
            let trimmed = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if elementName.hasSuffix("shortVersionString") {
                    currentShortVersionString = trimmed
                } else if elementName.hasSuffix("version") {
                    currentVersion = trimmed
                }
            }
        }
        if elementName == "item" {
            items.append(SparkleAppcastItem(version: currentVersion, shortVersionString: currentShortVersionString))
            isInsideItem = false
        }
    }
}
