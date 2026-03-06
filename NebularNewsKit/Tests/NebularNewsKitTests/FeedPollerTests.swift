import Testing
import SwiftData
import FeedKit
@testable import NebularNewsKit

// MARK: - Mock Fetcher

/// A mock feed fetcher that returns canned responses for testing.
struct MockFeedFetcher: FeedFetcherProtocol, @unchecked Sendable {
    var responses: [String: Result<FeedFetchResult, Error>] = [:]

    func fetch(url: String, etag: String?, lastModified: String?) async throws -> FeedFetchResult {
        guard let result = responses[url] else {
            throw FeedFetchError.invalidURL
        }
        return try result.get()
    }
}

@Suite("FeedPoller")
struct FeedPollerTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    /// Generate minimal valid RSS XML for testing.
    private func makeRSSXML(title: String = "Test Feed", items: [(String, String)]) -> Data {
        var itemsXML = ""
        for (itemTitle, itemLink) in items {
            itemsXML += """
                <item>
                    <title>\(itemTitle)</title>
                    <link>\(itemLink)</link>
                    <description>Description of \(itemTitle)</description>
                </item>
            """
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
            <channel>
                <title>\(title)</title>
                <link>https://example.com</link>
                \(itemsXML)
            </channel>
        </rss>
        """
        return Data(xml.utf8)
    }

    // MARK: - Tests

    @Test("Poll inserts new articles from RSS feed")
    func pollInsertsArticles() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        // Add a feed
        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "")

        // Set up mock fetcher with RSS data
        var mockFetcher = MockFeedFetcher()
        mockFetcher.responses["https://example.com/feed.xml"] = .success(FeedFetchResult(
            data: makeRSSXML(title: "Example Blog", items: [
                ("First Post", "https://example.com/post-1"),
                ("Second Post", "https://example.com/post-2"),
            ]),
            httpStatus: 200,
            etag: "\"abc123\"",
            lastModified: "Wed, 01 Jan 2025 00:00:00 GMT"
        ))

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)

        // Poll
        let result = await poller.pollAllFeeds(bypassBackoff: true)

        #expect(result.feedsPolled == 1)
        #expect(result.newArticles == 2)
        #expect(result.errors == 0)

        // Verify articles were stored
        let filter = ArticleFilter()
        let articles = await articleRepo.list(filter: filter, sort: .newest, limit: 100, offset: 0)
        #expect(articles.count == 2)

        // Verify feed metadata was updated (title auto-detected)
        let updatedFeed = await feedRepo.get(id: feed.id)
        #expect(updatedFeed?.title == "Example Blog")
        #expect(updatedFeed?.etag == "\"abc123\"")
        #expect(updatedFeed?.consecutiveErrors == 0)
    }

    @Test("Poll handles 304 Not Modified")
    func pollHandles304() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        var mockFetcher = MockFeedFetcher()
        mockFetcher.responses["https://example.com/feed.xml"] = .success(FeedFetchResult(
            data: Data(),
            httpStatus: 304,
            etag: "\"abc123\"",
            wasNotModified: true
        ))

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)
        let result = await poller.pollAllFeeds(bypassBackoff: true)

        #expect(result.feedsPolled == 1)
        #expect(result.newArticles == 0)

        // Verify no articles were inserted
        let articles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        #expect(articles.isEmpty)

        // Poll success was recorded
        let updatedFeed = await feedRepo.get(id: feed.id)
        #expect(updatedFeed?.lastPolledAt != nil)
    }

    @Test("Deduplication prevents re-inserting existing articles")
    func deduplication() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        let rssData = makeRSSXML(items: [
            ("Same Article", "https://example.com/same"),
        ])

        var mockFetcher = MockFeedFetcher()
        mockFetcher.responses["https://example.com/feed.xml"] = .success(FeedFetchResult(
            data: rssData,
            httpStatus: 200
        ))

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)

        // Poll twice
        let first = await poller.pollAllFeeds(bypassBackoff: true)
        let second = await poller.pollAllFeeds(bypassBackoff: true)

        #expect(first.newArticles == 1)
        #expect(second.newArticles == 0) // Deduped!

        // Only one article in DB
        let articles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        #expect(articles.count == 1)
    }

    @Test("Poll records errors correctly")
    func pollRecordsErrors() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://broken.com/feed.xml", title: "Broken")

        var mockFetcher = MockFeedFetcher()
        mockFetcher.responses["https://broken.com/feed.xml"] = .failure(FeedFetchError.timeout)

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)
        let result = await poller.pollAllFeeds(bypassBackoff: true)

        #expect(result.errors == 1)

        let updatedFeed = await feedRepo.get(id: feed.id)
        #expect(updatedFeed?.consecutiveErrors == 1)
        #expect(updatedFeed?.errorMessage == "Request timed out")
    }

    @Test("Disabled feeds are skipped")
    func disabledFeedsSkipped() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")
        try await feedRepo.setEnabled(id: feed.id, enabled: false)

        let mockFetcher = MockFeedFetcher() // No responses configured — would error if called

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)
        let result = await poller.pollAllFeeds(bypassBackoff: true)

        #expect(result.feedsPolled == 0)
    }

    @Test("Cleanup deletes old articles")
    func cleanupOldArticles() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        // Insert an article with old fetchedAt
        let oldArticle = ParsedArticle(
            url: "https://example.com/old",
            title: "Old Article",
            contentHash: "oldhash123"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: oldArticle)

        // Manually set fetchedAt to 100 days ago
        let articles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        if let article = articles.first {
            article.fetchedAt = Date(timeIntervalSinceNow: -100 * 86400)
        }

        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let deleted = await poller.cleanupOldArticles(retentionDays: 90)

        #expect(deleted == 1)
    }
}
