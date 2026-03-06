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
    func mapAtomEntry() {
        let feed = makeAtomFeed(entries: [
            makeAtomEntry(
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
    func mapJSONFeedItem() {
        let feed = makeJSONFeed(items: [
            makeJSONFeedItem(
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

    private func makeAtomFeed(entries: [AtomFeedEntry]) -> AtomFeed {
        let feed = AtomFeed()
        feed.entries = entries
        return feed
    }

    private func makeAtomEntry(
        title: String? = nil,
        alternateLink: String? = nil,
        contentValue: String? = nil,
        authorName: String? = nil,
        published: Date? = nil
    ) -> AtomFeedEntry {
        let entry = AtomFeedEntry()
        entry.title = title
        if let alternateLink {
            let link = AtomFeedEntryLink()
            link.attributes = AtomFeedEntryLink.Attributes()
            link.attributes?.href = alternateLink
            link.attributes?.rel = "alternate"
            entry.links = [link]
        }
        if let contentValue {
            entry.content = AtomFeedEntryContent()
            entry.content?.value = contentValue
        }
        if let authorName {
            let author = AtomFeedEntryAuthor()
            author.name = authorName
            entry.authors = [author]
        }
        entry.published = published
        return entry
    }

    private func makeJSONFeed(items: [JSONFeedItem]) -> JSONFeed {
        var feed = JSONFeed()
        feed.title = "Test JSON Feed"
        feed.items = items
        return feed
    }

    private func makeJSONFeedItem(
        title: String? = nil,
        url: String? = nil,
        contentHtml: String? = nil,
        summary: String? = nil,
        authorName: String? = nil,
        datePublished: Date? = nil
    ) -> JSONFeedItem {
        var item = JSONFeedItem()
        item.title = title
        item.url = url
        item.contentHtml = contentHtml
        item.summary = summary
        if let authorName {
            item.author = JSONFeedAuthor()
            item.author?.name = authorName
        }
        item.datePublished = datePublished
        return item
    }
}
