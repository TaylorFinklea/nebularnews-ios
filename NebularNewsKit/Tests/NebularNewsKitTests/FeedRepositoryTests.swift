import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("FeedRepository")
struct FeedRepositoryTests {

    private func makeRepo() throws -> LocalFeedRepository {
        let container = try makeInMemoryModelContainer()
        return LocalFeedRepository(modelContainer: container)
    }

    @Test("Add and list feeds")
    func addAndList() async throws {
        let repo = try makeRepo()

        let feed = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "Test Feed")
        #expect(feed.feedUrl == "https://example.com/feed.xml")
        #expect(feed.title == "Test Feed")

        let feeds = await repo.list()
        #expect(feeds.count == 1)
        #expect(feeds.first?.id == feed.id)
    }

    @Test("Duplicate feed URL returns existing")
    func duplicateFeed() async throws {
        let repo = try makeRepo()

        let first = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "First")
        let second = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "Second")

        #expect(first.id == second.id)
        let feeds = await repo.list()
        #expect(feeds.count == 1)
    }

    @Test("Legacy ATS-hostile URLs are normalized on add")
    func normalizesLegacyATSURLs() async throws {
        let repo = try makeRepo()

        let pbsFeed = try await repo.add(
            feedUrl: "https://feeds.pbs.org/newshour/rss/headlines",
            title: "PBS"
        )
        let jmlrFeed = try await repo.add(
            feedUrl: "http://www.jmlr.org/jmlr.xml",
            title: "JMLR"
        )

        #expect(pbsFeed.feedUrl == "https://pbs.org/newshour/feeds/rss/headlines")
        #expect(jmlrFeed.feedUrl == "https://www.jmlr.org/jmlr.xml")
    }

    @Test("URL normalization deduplicates equivalent feeds")
    func deduplicatesNormalizedFeedURLs() async throws {
        let repo = try makeRepo()

        let first = try await repo.add(
            feedUrl: "https://feeds.pbs.org/newshour/rss/headlines",
            title: "PBS Legacy"
        )
        let second = try await repo.add(
            feedUrl: "https://pbs.org/newshour/feeds/rss/headlines",
            title: "PBS Canonical"
        )

        #expect(first.id == second.id)
        let feeds = await repo.list()
        #expect(feeds.count == 1)
    }

    @Test("Listing repairs previously stored legacy URLs")
    func listRepairsLegacyStoredURLs() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let legacyFeed = Feed(feedUrl: "https://feeds.pbs.org/newshour/rss/politics", title: "PBS Politics")
        legacyFeed.feedUrl = "https://feeds.pbs.org/newshour/rss/politics"
        context.insert(legacyFeed)
        try context.save()

        let repo = LocalFeedRepository(modelContainer: container)
        let feeds = await repo.list()
        let repaired = try #require(feeds.first)

        #expect(repaired.feedUrl == "https://pbs.org/newshour/feeds/rss/politics")
    }

    @Test("Delete feed")
    func deleteFeed() async throws {
        let repo = try makeRepo()

        let feed = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "Test")
        try await repo.delete(id: feed.id)

        let feeds = await repo.list()
        #expect(feeds.isEmpty)
    }

    @Test("Toggle enabled state")
    func toggleEnabled() async throws {
        let repo = try makeRepo()

        let feed = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "Test")
        #expect(feed.isEnabled == true)

        try await repo.setEnabled(id: feed.id, enabled: false)
        let updated = await repo.get(id: feed.id)
        #expect(updated?.isEnabled == false)
    }

    @Test("Record poll success clears errors")
    func pollSuccess() async throws {
        let repo = try makeRepo()

        let feed = try await repo.add(feedUrl: "https://example.com/feed.xml", title: "Test")
        try await repo.recordPollError(id: feed.id, message: "timeout")

        let errored = await repo.get(id: feed.id)
        #expect(errored?.consecutiveErrors == 1)

        try await repo.recordPollSuccess(id: feed.id, etag: "abc", lastModified: nil, hadNewItems: true)
        let fixed = await repo.get(id: feed.id)
        #expect(fixed?.consecutiveErrors == 0)
        #expect(fixed?.errorMessage == nil)
        #expect(fixed?.etag == "abc")
        #expect(fixed?.lastNewItemAt != nil)
    }
}
