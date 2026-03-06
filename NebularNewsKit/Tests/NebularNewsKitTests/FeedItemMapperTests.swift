import Foundation
import Testing
import FeedKit
@testable import NebularNewsKit

@Suite("FeedItemMapper")
struct FeedItemMapperTests {

    // MARK: - RSS Mapping

    @Test("Maps RSS item with all fields")
    func mapRSSItemFull() {
        let feed = makeRSSFeed(items: [
            makeRSSItem(
                title: "Test Article",
                link: "https://example.com/article-1",
                description: "A short description",
                contentEncoded: "<p>Full content here</p>",
                author: "Jane Doe",
                pubDate: Date(timeIntervalSince1970: 1700000000)
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .rss(feed))
        #expect(articles.count == 1)

        let article = articles[0]
        #expect(article.title == "Test Article")
        #expect(article.url == "https://example.com/article-1")
        #expect(article.author == "Jane Doe")
        #expect(article.contentHtml == "<p>Full content here</p>")
        #expect(article.excerpt == "A short description")
        #expect(article.publishedAt != nil)
        #expect(!article.contentHash.isEmpty)
    }

    @Test("RSS prefers content:encoded over description for HTML")
    func rssContentPriority() {
        let feed = makeRSSFeed(items: [
            makeRSSItem(
                title: "Title",
                link: "https://example.com/1",
                description: "<p>Short</p>",
                contentEncoded: "<article><h1>Full Article</h1><p>Detailed content</p></article>"
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .rss(feed))
        // contentHtml should be the content:encoded, not description
        #expect(articles[0].contentHtml?.contains("Full Article") == true)
    }

    @Test("RSS falls back to description when no content:encoded")
    func rssFallbackToDescription() {
        let feed = makeRSSFeed(items: [
            makeRSSItem(
                title: "Title",
                link: "https://example.com/1",
                description: "<p>Only description</p>",
                contentEncoded: nil
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .rss(feed))
        #expect(articles[0].contentHtml == "<p>Only description</p>")
    }

    @Test("RSS skips items with neither URL nor title")
    func rssSkipEmpty() {
        let feed = makeRSSFeed(items: [
            makeRSSItem(title: nil, link: nil, description: "orphan")
        ])

        let articles = FeedItemMapper.extractArticles(from: .rss(feed))
        #expect(articles.isEmpty)
    }

    @Test("RSS extracts feed metadata")
    func rssMetadata() {
        let feed = makeRSSFeed(
            title: "My Blog",
            link: "https://myblog.com",
            items: []
        )

        let metadata = FeedItemMapper.extractMetadata(from: .rss(feed))
        #expect(metadata.title == "My Blog")
        #expect(metadata.siteUrl == "https://myblog.com")
    }

    // MARK: - Atom Mapping

    @Test("Maps Atom entry")
    func mapAtomEntry() throws {
        let feed = try makeAtomFeed(entriesXML: [
            makeAtomEntryXML(
                title: "Atom Article",
                alternateLink: "https://example.com/atom-1",
                contentValue: "<p>Atom content</p>",
                authorName: "John Smith",
                published: Date(timeIntervalSince1970: 1700000000)
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .atom(feed))
        #expect(articles.count == 1)
        #expect(articles[0].title == "Atom Article")
        #expect(articles[0].url == "https://example.com/atom-1")
        #expect(articles[0].author == "John Smith")
        #expect(articles[0].contentHtml == "<p>Atom content</p>")
    }

    // MARK: - JSON Feed Mapping

    @Test("Maps JSON Feed item")
    func mapJSONFeedItem() throws {
        let feed = try makeJSONFeed(itemsJSON: [
            makeJSONFeedItemJSON(
                id: "json-1",
                title: "JSON Article",
                url: "https://example.com/json-1",
                contentHtml: "<p>JSON content</p>",
                summary: "A summary",
                authorName: "Alice",
                datePublished: Date(timeIntervalSince1970: 1700000000)
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .json(feed))
        #expect(articles.count == 1)
        #expect(articles[0].title == "JSON Article")
        #expect(articles[0].url == "https://example.com/json-1")
        #expect(articles[0].contentHtml == "<p>JSON content</p>")
        #expect(articles[0].excerpt == "A summary")
    }

    // MARK: - Hash Stability

    @Test("Hash is deterministic for same URL")
    func hashStability() {
        let hash1 = FeedItemMapper.computeHash(url: "https://example.com/1", title: "Title", publishedAt: nil)
        let hash2 = FeedItemMapper.computeHash(url: "https://example.com/1", title: "Title", publishedAt: nil)
        #expect(hash1 == hash2)
    }

    @Test("Hash uses URL when available, ignores title")
    func hashPrefersURL() {
        let hashWithUrl = FeedItemMapper.computeHash(url: "https://example.com/1", title: "A", publishedAt: nil)
        let hashSameUrlDiffTitle = FeedItemMapper.computeHash(url: "https://example.com/1", title: "B", publishedAt: nil)
        #expect(hashWithUrl == hashSameUrlDiffTitle)
    }

    @Test("Hash falls back to title+date when no URL")
    func hashFallback() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let hash1 = FeedItemMapper.computeHash(url: nil, title: "Same Title", publishedAt: date)
        let hash2 = FeedItemMapper.computeHash(url: nil, title: "Same Title", publishedAt: date)
        #expect(hash1 == hash2)

        let hash3 = FeedItemMapper.computeHash(url: nil, title: "Different Title", publishedAt: date)
        #expect(hash1 != hash3)
    }

    @Test("Strips HTML tags from excerpt")
    func htmlStripping() {
        let feed = makeRSSFeed(items: [
            makeRSSItem(
                title: "Test",
                link: "https://example.com/1",
                description: "<p>Hello &amp; <strong>world</strong></p>"
            )
        ])

        let articles = FeedItemMapper.extractArticles(from: .rss(feed))
        #expect(articles[0].excerpt == "Hello & world")
    }

    // MARK: - Test Helpers

    private func makeRSSFeed(title: String = "Test Feed", link: String = "https://example.com", items: [RSSFeedItem]) -> RSSFeed {
        let feed = RSSFeed()
        feed.title = title
        feed.link = link
        feed.items = items
        return feed
    }

    private func makeRSSItem(
        title: String? = nil,
        link: String? = nil,
        description: String? = nil,
        contentEncoded: String? = nil,
        author: String? = nil,
        pubDate: Date? = nil
    ) -> RSSFeedItem {
        let item = RSSFeedItem()
        item.title = title
        item.link = link
        item.description = description
        if let contentEncoded {
            item.content = ContentNamespace()
            item.content?.contentEncoded = contentEncoded
        }
        item.author = author
        item.pubDate = pubDate
        return item
    }

    private func makeAtomFeed(entriesXML: [String]) throws -> AtomFeed {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Test Feed</title>
            \(entriesXML.joined(separator: "\n"))
        </feed>
        """

        let feed = try FeedParser(data: Data(xml.utf8)).parse().get()
        guard let atomFeed = feed.atomFeed else {
            fatalError("Expected Atom feed in test helper")
        }
        return atomFeed
    }

    private func makeAtomEntryXML(
        title: String? = nil,
        alternateLink: String? = nil,
        contentValue: String? = nil,
        authorName: String? = nil,
        published: Date? = nil
    ) -> String {
        let isoDate = published.map(iso8601String) ?? "2023-11-14T22:13:20Z"
        let titleXML = title.map { "<title>\($0.xmlEscaped)</title>" } ?? ""
        let linkXML = alternateLink.map { "<link rel=\"alternate\" href=\"\($0.xmlEscaped)\" />" } ?? ""
        let contentXML = contentValue.map { "<content type=\"html\"><![CDATA[\($0)]]></content>" } ?? ""
        let authorXML = authorName.map { "<author><name>\($0.xmlEscaped)</name></author>" } ?? ""

        return """
        <entry>
            <id>urn:uuid:\(UUID().uuidString.lowercased())</id>
            \(titleXML)
            \(linkXML)
            \(authorXML)
            <updated>\(isoDate)</updated>
            <published>\(isoDate)</published>
            \(contentXML)
        </entry>
        """
    }

    private func makeJSONFeed(itemsJSON: [String]) throws -> JSONFeed {
        let json = """
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Test JSON Feed",
          "items": [
            \(itemsJSON.joined(separator: ",\n"))
          ]
        }
        """

        let feed = try FeedParser(data: Data(json.utf8)).parse().get()
        guard let jsonFeed = feed.jsonFeed else {
            fatalError("Expected JSON feed in test helper")
        }
        return jsonFeed
    }

    private func makeJSONFeedItemJSON(
        id: String,
        title: String? = nil,
        url: String? = nil,
        contentHtml: String? = nil,
        summary: String? = nil,
        authorName: String? = nil,
        datePublished: Date? = nil
    ) -> String {
        var fields: [String] = ["\"id\": \"\(id.jsonEscaped)\""]

        if let title {
            fields.append("\"title\": \"\(title.jsonEscaped)\"")
        }
        if let url {
            fields.append("\"url\": \"\(url.jsonEscaped)\"")
        }
        if let contentHtml {
            fields.append("\"content_html\": \"\(contentHtml.jsonEscaped)\"")
        }
        if let summary {
            fields.append("\"summary\": \"\(summary.jsonEscaped)\"")
        }
        if let authorName {
            fields.append("\"author\": { \"name\": \"\(authorName.jsonEscaped)\" }")
        }
        if let datePublished {
            fields.append("\"date_published\": \"\(iso8601String(datePublished))\"")
        }

        return "{ \(fields.joined(separator: ", ")) }"
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    var jsonEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
