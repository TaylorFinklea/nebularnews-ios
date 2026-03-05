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
