import Foundation
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

    private func makeRSSXMLWithDates(title: String = "Test Feed", items: [(title: String, link: String, publishedAt: Date)]) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var itemsXML = ""
        for item in items {
            itemsXML += """
                <item>
                    <title>\(item.title)</title>
                    <link>\(item.link)</link>
                    <description>Description of \(item.title)</description>
                    <pubDate>\(formatter.string(from: item.publishedAt))</pubDate>
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

        _ = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

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

    @Test("Cleanup deletes old articles by fetched date when published date is missing")
    func cleanupOldArticlesByFetchedDateFallback() async throws {
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

    @Test("Cleanup deletes newly fetched articles when their published date is outside retention")
    func cleanupOldArticlesByPublishedDate() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        let oldArticle = ParsedArticle(
            url: "https://example.com/archive",
            title: "Archive Article",
            publishedAt: Date(timeIntervalSinceNow: -120 * 86400),
            contentHash: "archivehash123"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: oldArticle)

        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let deleted = await poller.cleanupOldArticles(retentionDays: 90)

        #expect(deleted == 1)

        let remaining = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        #expect(remaining.isEmpty)
    }

    @Test("Cleanup keeps articles when published date is still within retention")
    func cleanupKeepsRecentlyPublishedArticles() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        let recentArticle = ParsedArticle(
            url: "https://example.com/recent",
            title: "Recent Article",
            publishedAt: Date(timeIntervalSinceNow: -7 * 86400),
            contentHash: "recenthash123"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: recentArticle)

        let articles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        if let article = articles.first {
            article.fetchedAt = Date(timeIntervalSinceNow: -100 * 86400)
        }

        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let deleted = await poller.cleanupOldArticles(retentionDays: 90)

        #expect(deleted == 0)

        let remaining = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        #expect(remaining.count == 1)
    }

    @Test("Cleanup keeps saved articles even when they are older than retention")
    func cleanupKeepsSavedArticles() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        let savedArticle = ParsedArticle(
            url: "https://example.com/saved-archive",
            title: "Saved Archive Article",
            publishedAt: Date(timeIntervalSinceNow: -120 * 86400),
            contentHash: "savedarchivehash123"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: savedArticle)

        let articles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        let article = try #require(articles.first)
        article.addToReadingList(at: Date())

        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let deleted = await poller.cleanupOldArticles(retentionDays: 90)

        #expect(deleted == 0)

        let remaining = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        #expect(remaining.count == 1)
        #expect(remaining.first?.isInReadingList == true)
    }

    @Test("Per-feed trimming keeps the newest unsaved articles and preserves saved ones")
    func trimExcessArticlesPerFeedKeepsNewestAndSaved() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Test")

        for index in 0..<5 {
            let article = ParsedArticle(
                url: "https://example.com/article-\(index)",
                title: "Article \(index)",
                publishedAt: Date(timeIntervalSinceNow: -Double(index) * 86400),
                contentHash: "hash-\(index)"
            )
            try await articleRepo.insertForFeed(feedId: feed.id, article: article)
        }

        let allArticles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 100, offset: 0)
        let savedArticle = try #require(allArticles.first(where: { $0.title == "Article 4" }))
        savedArticle.addToReadingList(at: Date())

        let deleted = try await articleRepo.trimExcessArticlesPerFeed(maxPerFeed: 2)
        #expect(deleted == 2)

        var filter = ArticleFilter()
        filter.feedId = feed.id
        let remaining = await articleRepo.list(filter: filter, sort: .newest, limit: 100, offset: 0)
        let titles = Set(remaining.compactMap(\.title))

        #expect(remaining.count == 3)
        #expect(titles == ["Article 0", "Article 1", "Article 4"])
        #expect(remaining.contains(where: { $0.title == "Article 4" && $0.isInReadingList }))
    }

    @Test("Single-feed polls can enforce retention and per-feed limits immediately")
    func singleFeedPollingEnforcesStoragePolicies() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Roshar")

        let now = Date()
        let feedItems = [
            (title: "Recent 0", link: "https://example.com/recent-0", publishedAt: now),
            (title: "Recent 1", link: "https://example.com/recent-1", publishedAt: now.addingTimeInterval(-86400)),
            (title: "Recent 2", link: "https://example.com/recent-2", publishedAt: now.addingTimeInterval(-2 * 86400)),
            (title: "Archive 0", link: "https://example.com/archive-0", publishedAt: now.addingTimeInterval(-120 * 86400)),
            (title: "Archive 1", link: "https://example.com/archive-1", publishedAt: now.addingTimeInterval(-121 * 86400)),
            (title: "Archive 2", link: "https://example.com/archive-2", publishedAt: now.addingTimeInterval(-122 * 86400)),
        ]

        var mockFetcher = MockFeedFetcher()
        mockFetcher.responses["https://example.com/feed.xml"] = .success(FeedFetchResult(
            data: makeRSSXMLWithDates(title: "Roshar", items: feedItems),
            httpStatus: 200
        ))

        let poller = FeedPoller(fetcher: mockFetcher, feedRepo: feedRepo, articleRepo: articleRepo)

        let pollResult = try #require(await poller.pollFeed(id: feed.id))
        #expect(pollResult.newArticles == 6)

        let storage = await poller.enforceArticleStoragePolicies(
            retentionDays: 90,
            maxArticlesPerFeed: 2
        )

        #expect(storage.deleted == 3)
        #expect(storage.trimmed == 1)

        var filter = ArticleFilter()
        filter.feedId = feed.id
        let remaining = await articleRepo.list(filter: filter, sort: .newest, limit: 100, offset: 0)

        #expect(remaining.count == 2)
        #expect(Set(remaining.compactMap(\.title)) == ["Recent 0", "Recent 1"])
    }
}
