import Foundation
import Testing
@testable import NebularNewsKit

@Suite("OPMLParser")
struct OPMLParserTests {

    @Test("Parses top-level and nested feed outlines")
    func parsesNestedFeeds() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Tech">
              <outline text="OpenAI News" title="OpenAI News" type="rss" xmlUrl="https://example.com/openai.xml" htmlUrl="https://example.com/openai" />
              <outline text="AI Weekly" type="rss" xmlUrl="https://example.com/weekly.xml" />
            </outline>
            <outline text="Standalone" type="rss" xmlUrl="https://example.com/standalone.xml" />
          </body>
        </opml>
        """

        let entries = try OPMLParser.parse(string: opml)

        #expect(entries.count == 3)
        #expect(entries[0] == OPMLFeedEntry(feedURL: "https://example.com/openai.xml", title: "OpenAI News", siteURL: "https://example.com/openai"))
        #expect(entries[1] == OPMLFeedEntry(feedURL: "https://example.com/weekly.xml", title: "AI Weekly"))
        #expect(entries[2] == OPMLFeedEntry(feedURL: "https://example.com/standalone.xml", title: "Standalone"))
    }

    @Test("Skips folder outlines without xmlUrl")
    func skipsFolders() throws {
        let opml = """
        <opml version="2.0">
          <body>
            <outline text="Folder Only">
              <outline text="Nested Folder" />
            </outline>
          </body>
        </opml>
        """

        let entries = try OPMLParser.parse(string: opml)
        #expect(entries.isEmpty)
    }

    @Test("Throws on malformed OPML")
    func throwsOnMalformedDocument() {
        #expect(throws: OPMLParserError.self) {
            try OPMLParser.parse(string: "<opml><body><outline")
        }
    }
}
