import Foundation

struct SparkleAppcastItem: Sendable, Equatable {
    let version: String?
    let shortVersionString: String?
    let enclosureURL: URL?
    let edSignatureBase64: String?
}

/// Parses a Sparkle appcast XML feed belonging to another app. Patchly only reads
/// these feeds — it does not use the Sparkle framework itself. See CONTEXT.md.
final class SparkleAppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var items: [SparkleAppcastItem] = []
    private var currentVersion: String?
    private var currentShortVersionString: String?
    private var currentEnclosureURL: URL?
    private var currentEdSignatureBase64: String?
    private var currentElementText = ""
    private var isInsideItem = false

    static func parse(data: Data) -> [SparkleAppcastItem] {
        let delegate = SparkleAppcastParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        xmlParser.parse()
        return delegate.items
    }

    /// The item with the highest version across all items, preferring
    /// `shortVersionString` over `version` for comparison.
    static func latestItem(among items: [SparkleAppcastItem]) -> SparkleAppcastItem? {
        items.max { lhs, rhs in
            let lhsVersion = lhs.shortVersionString ?? lhs.version ?? ""
            let rhsVersion = rhs.shortVersionString ?? rhs.version ?? ""
            return VersionComparator.compare(lhsVersion, rhsVersion) == .orderedAscending
        }
    }

    static func latestVersion(among items: [SparkleAppcastItem]) -> String? {
        latestItem(among: items).flatMap { $0.shortVersionString ?? $0.version }
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
            currentEnclosureURL = nil
            currentEdSignatureBase64 = nil
        }
        if elementName == "enclosure", isInsideItem {
            for (key, value) in attributeDict {
                if key == "url" {
                    currentEnclosureURL = URL(string: value)
                } else if key.hasSuffix("edSignature") {
                    currentEdSignatureBase64 = value
                } else if key.hasSuffix("shortVersionString") {
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
            items.append(SparkleAppcastItem(
                version: currentVersion,
                shortVersionString: currentShortVersionString,
                enclosureURL: currentEnclosureURL,
                edSignatureBase64: currentEdSignatureBase64
            ))
            isInsideItem = false
        }
    }
}
