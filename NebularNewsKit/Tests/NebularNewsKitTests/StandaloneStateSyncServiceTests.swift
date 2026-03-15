import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("StandaloneStateSyncService")
struct StandaloneStateSyncServiceTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @Test("Bootstrap seeds synced models from local standalone state exactly once")
    func bootstrapSeedsSyncedModelsFromLocalState() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let settings = AppSettings()
        settings.archiveAfterDays = 21
        settings.retentionDays = 21
        settings.deleteArchivedAfterDays = 45
        settings.maxArticlesPerFeed = 40
        settings.searchArchivedByDefault = true
        settings.updatedAt = Date(timeIntervalSince1970: 100)
        context.insert(settings)

        let feed = Feed(feedUrl: "https://example.com/feed.xml", title: "Example")
        context.insert(feed)

        let article = Article(canonicalUrl: "https://example.com/articles/1", title: "One")
        article.feed = feed
        article.markRead(at: Date(timeIntervalSince1970: 200))
        article.addToReadingList(at: Date(timeIntervalSince1970: 210))
        article.setReaction(value: 1, reasonCodes: ["matches_interests"], at: Date(timeIntervalSince1970: 220))
        article.refreshQueryState()
        context.insert(article)
        try context.save()

        let service = StandaloneStateSyncService(modelContainer: container)
        await service.bootstrap()
        await service.bootstrap()

        let syncedFeeds = try context.fetch(FetchDescriptor<SyncedFeedSubscription>())
        let syncedStates = try context.fetch(FetchDescriptor<SyncedArticleState>())
        let syncedPrefs = try context.fetch(FetchDescriptor<SyncedPreferences>())

        #expect(syncedFeeds.count == 1)
        #expect(syncedStates.count == 1)
        #expect(syncedPrefs.count == 1)
        #expect(syncedFeeds.first?.feedKey == feed.feedKey)
        #expect(syncedStates.first?.articleKey == article.articleKey)
        #expect(syncedStates.first?.feedKey == feed.feedKey)
        #expect(syncedPrefs.first?.archiveAfterDays == 21)
        #expect(syncedPrefs.first?.maxArticlesPerFeed == 40)
    }

    @Test("Bootstrap projects synced preferences and subscriptions into local cache")
    func bootstrapProjectsSyncedStateIntoLocalCache() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let settings = AppSettings()
        settings.archiveAfterDays = 13
        settings.retentionDays = 13
        settings.deleteArchivedAfterDays = 30
        settings.maxArticlesPerFeed = 50
        settings.searchArchivedByDefault = false
        settings.syncedPreferencesUpdatedAt = Date(timeIntervalSince1970: 10)
        settings.updatedAt = Date(timeIntervalSince1970: 10)
        context.insert(settings)

        context.insert(
            SyncedPreferences(
                archiveAfterDays: 7,
                deleteArchivedAfterDays: 14,
                maxArticlesPerFeed: 25,
                searchArchivedByDefault: true,
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )

        context.insert(
            SyncedFeedSubscription(
                feedKey: normalizedFeedKey(from: "https://example.com/synced.xml") ?? "https://example.com/synced.xml",
                feedURL: "https://example.com/synced.xml",
                titleOverride: "Synced Feed",
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 30)
            )
        )
        try context.save()

        let service = StandaloneStateSyncService(modelContainer: container)
        await service.bootstrap()

        let projectedSettings = try #require((try context.fetch(FetchDescriptor<AppSettings>())).first)
        let projectedFeed = try #require((try context.fetch(FetchDescriptor<Feed>())).first)

        #expect(projectedSettings.archiveAfterDays == 7)
        #expect(projectedSettings.deleteArchivedAfterDays == 14)
        #expect(projectedSettings.maxArticlesPerFeed == 25)
        #expect(projectedSettings.searchArchivedByDefault)
        #expect(projectedFeed.feedUrl == "https://example.com/synced.xml")
        #expect(projectedFeed.title == "Synced Feed")
        #expect(projectedFeed.isEnabled)
    }

    @Test("Insert for feed hydrates local article state from synced article state")
    func insertForFeedHydratesFromSyncedArticleState() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let feed = Feed(feedUrl: "https://example.com/feed.xml", title: "Example")
        context.insert(feed)
        context.insert(
            SyncedArticleState(
                articleKey: "https://example.com/articles/2",
                feedKey: feed.feedKey,
                isRead: true,
                readAt: Date(timeIntervalSince1970: 300),
                dismissedAt: nil,
                readingListAddedAt: Date(timeIntervalSince1970: 301),
                reactionValue: 1,
                reactionReasonCodes: "matches_interests",
                reactionUpdatedAt: Date(timeIntervalSince1970: 302),
                updatedAt: Date(timeIntervalSince1970: 302)
            )
        )
        try context.save()

        let repo = LocalArticleRepository(modelContainer: container)
        try await repo.insertForFeed(
            feedId: feed.id,
            article: ParsedArticle(
                url: "https://example.com/articles/2",
                title: "Hydrated",
                publishedAt: Date(timeIntervalSince1970: 299),
                contentHtml: "<p>Hello</p>",
                excerpt: "Hello",
                imageUrl: nil,
                contentHash: "abc123"
            )
        )

        let article = try #require((try context.fetch(FetchDescriptor<Article>())).first)
        #expect(article.articleKey == "https://example.com/articles/2")
        #expect(article.isRead)
        #expect(article.isInReadingList)
        #expect(article.reactionValue == 1)
        #expect(article.reactionReasonCodes == "matches_interests")
    }

    @Test("Local article state writes through to synced article state")
    func localArticleActionsWriteThroughToSyncedState() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let feed = Feed(feedUrl: "https://example.com/feed.xml", title: "Example")
        context.insert(feed)

        let article = Article(canonicalUrl: "https://example.com/articles/3", title: "Three")
        article.feed = feed
        article.contentHash = "hash-3"
        article.refreshQueryState()
        context.insert(article)
        try context.save()

        let repo = LocalArticleRepository(modelContainer: container)
        try await repo.markRead(id: article.id, isRead: true)
        try await repo.setReadingList(id: article.id, isSaved: true)
        try await repo.react(id: article.id, value: -1, reasonCodes: ["off_topic"])

        let synced = try #require((try context.fetch(FetchDescriptor<SyncedArticleState>())).first)
        #expect(synced.articleKey == article.articleKey)
        #expect(synced.feedKey == feed.feedKey)
        #expect(synced.isRead)
        #expect(synced.readingListAddedAt != nil)
        #expect(synced.reactionValue == -1)
        #expect(synced.reactionReasonCodes == "off_topic")
        #expect(synced.reactionUpdatedAt != nil)
    }

    @Test("Bootstrap backfills missing synced article-state feed keys from local articles")
    func bootstrapBackfillsMissingSyncedArticleStateFeedKeys() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let feed = Feed(feedUrl: "https://example.com/feed.xml", title: "Example")
        context.insert(feed)

        let article = Article(canonicalUrl: "https://example.com/articles/9", title: "Nine")
        article.feed = feed
        article.refreshQueryState()
        context.insert(article)
        context.insert(
            SyncedArticleState(
                articleKey: article.articleKey,
                feedKey: "",
                isRead: true,
                readAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        try context.save()

        let service = StandaloneStateSyncService(modelContainer: container)
        await service.bootstrap()

        let synced = try #require((try context.fetch(FetchDescriptor<SyncedArticleState>())).first)
        #expect(synced.feedKey == feed.feedKey)
    }
}
