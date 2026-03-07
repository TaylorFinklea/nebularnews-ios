import Foundation

public struct OPMLFeedEntry: Sendable, Hashable {
    public let feedURL: String
    public let title: String
    public let siteURL: String?

    public init(feedURL: String, title: String, siteURL: String? = nil) {
        self.feedURL = feedURL
        self.title = title
        self.siteURL = siteURL
    }
}

public enum OPMLParserError: LocalizedError {
    case invalidEncoding
    case malformedDocument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The OPML file could not be read as text."
        case .malformedDocument(let message):
            return message
        }
    }
}

public enum OPMLParser {
    public static func parse(data: Data) throws -> [OPMLFeedEntry] {
        guard !data.isEmpty else { return [] }

        let delegate = OPMLDocumentParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "The OPML document is malformed."
            throw OPMLParserError.malformedDocument(message)
        }

        return delegate.entries
    }

    public static func parse(string: String) throws -> [OPMLFeedEntry] {
        guard let data = string.data(using: .utf8) else {
            throw OPMLParserError.invalidEncoding
        }
        return try parse(data: data)
    }
}

private final class OPMLDocumentParser: NSObject, XMLParserDelegate {
    private(set) var entries: [OPMLFeedEntry] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard elementName.caseInsensitiveCompare("outline") == .orderedSame else {
            return
        }

        guard let feedURL = value(for: "xmlUrl", in: attributeDict)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !feedURL.isEmpty
        else {
            return
        }

        let title = value(for: "title", in: attributeDict)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = value(for: "text", in: attributeDict)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let siteURL = value(for: "htmlUrl", in: attributeDict)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = {
            if let title, !title.isEmpty { return title }
            if let text, !text.isEmpty { return text }
            return ""
        }()

        entries.append(
            OPMLFeedEntry(
                feedURL: feedURL,
                title: displayTitle,
                siteURL: siteURL?.isEmpty == true ? nil : siteURL
            )
        )
    }

    private func value(for key: String, in attributes: [String: String]) -> String? {
        if let exact = attributes[key] {
            return exact
        }

        let loweredKey = key.lowercased()
        return attributes.first { attribute, _ in
            attribute.lowercased() == loweredKey
        }?.value
    }
}
