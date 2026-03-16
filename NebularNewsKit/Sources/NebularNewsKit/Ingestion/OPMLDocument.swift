import Foundation

public enum OPMLDocument {
    public static func data(
        title: String = "Nebular News Feeds",
        entries: [OPMLFeedEntry]
    ) throws -> Data {
        let document = string(title: title, entries: entries)
        guard let data = document.data(using: .utf8) else {
            throw OPMLParserError.invalidEncoding
        }
        return data
    }

    public static func string(
        title: String = "Nebular News Feeds",
        entries: [OPMLFeedEntry]
    ) -> String {
        let lines = entries.map { entry in
            let titleAttribute = escapedAttribute(entry.title)
            let siteURLAttribute = entry.siteURL.map { " htmlUrl=\"\(escapedAttribute($0))\"" } ?? ""
            return "    <outline text=\"\(titleAttribute)\" title=\"\(titleAttribute)\" type=\"rss\" xmlUrl=\"\(escapedAttribute(entry.feedURL))\"\(siteURLAttribute) />"
        }

        let body = lines.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escapedText(title))</title>
          </head>
          <body>
        \(body)
          </body>
        </opml>
        """
    }

    private static func escapedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedAttribute(_ text: String) -> String {
        escapedText(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
