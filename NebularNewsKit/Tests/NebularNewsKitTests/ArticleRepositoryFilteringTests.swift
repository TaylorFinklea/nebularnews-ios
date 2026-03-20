import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("ArticleRepositoryFiltering")
struct ArticleRepositoryFilteringTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @discardableResult
    private func insertFeed(
        in context: ModelContext,
        title: String = "Test Feed",
        url: String = "https://example.com/feed.xml"
    ) throws -> Feed {
        let feed = Feed(feedUrl: url, title: title)
        context.insert(feed)
        try context.save()
        return feed
    }

    @discardableResult
    private func insertVisibleArticle(
        in context: ModelContext,
        feed: Feed,
        title: String,
        publishedAt: Date,
        score: Int
    ) throws -> Article {
        let article = Article(canonicalUrl: "https://example.com/\(UUID().uuidString)", title: title)
        article.feed = feed
        article.publishedAt = publishedAt
        article.score = score
        article.scoreStatus = LocalScoreStatus.ready.rawValue
        article.contentRevision = 1
        article.contentPreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        article.markScorePrepared(revision: currentPersonalizationVersion)
        context.insert(article)
        try context.save()
        return article
    }

    @Test("Feed page date range includes only articles within inclusive day bounds")
    func feedPageDateRangeFiltersInclusiveBounds() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context)
        let calendar = Calendar(identifier: .gregorian)

        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "March 1",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12)) ?? .now,
            score: 3
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "March 3",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 9)) ?? .now,
            score: 4
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "March 5",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 18)) ?? .now,
            score: 5
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "March 7",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8)) ?? .now,
            score: 2
        )

        var filter = ArticleFilter()
        filter.publishedAfter = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 0, minute: 0, second: 0))
        filter.publishedBefore = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23, minute: 59, second: 59))

        let repo = LocalArticleRepository(modelContainer: container)
        let articles = await repo.listFeedPage(filter: filter, sort: .newest, cursor: nil, limit: 10)

        #expect(articles.map(\.title) == ["March 5", "March 3"])
        let count = await repo.countFeed(filter: filter)
        #expect(count == 2)
    }

    @Test("Feed page oldest sort paginates in stable chronological order")
    func feedPageOldestSortPagesChronologically() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context)
        let calendar = Calendar(identifier: .gregorian)

        let articles = [
            ("Jan 1", calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now),
            ("Jan 2", calendar.date(from: DateComponents(year: 2026, month: 1, day: 2)) ?? .now),
            ("Jan 3", calendar.date(from: DateComponents(year: 2026, month: 1, day: 3)) ?? .now),
            ("Jan 4", calendar.date(from: DateComponents(year: 2026, month: 1, day: 4)) ?? .now)
        ]

        for (index, article) in articles.enumerated() {
            try insertVisibleArticle(
                in: context,
                feed: feed,
                title: article.0,
                publishedAt: article.1,
                score: index + 1
            )
        }

        let repo = LocalArticleRepository(modelContainer: container)
        let firstPage = await repo.listFeedPage(filter: ArticleFilter(), sort: .oldest, cursor: nil, limit: 2)
        #expect(firstPage.map(\.title) == ["Jan 1", "Jan 2"])

        let cursor = try #require(
            firstPage.last.map {
                ArticleListCursor(
                    sortDate: $0.querySortDate,
                    articleID: $0.id,
                    displayedScore: $0.queryDisplayedScore
                )
            }
        )

        let secondPage = await repo.listFeedPage(filter: ArticleFilter(), sort: .oldest, cursor: cursor, limit: 2)
        #expect(secondPage.map(\.title) == ["Jan 3", "Jan 4"])
    }

    @Test("Feed page score sort pages by score then recency")
    func feedPageScoreSortPagesByScoreThenDate() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context)
        let calendar = Calendar(identifier: .gregorian)

        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Score 5",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 6)) ?? .now,
            score: 5
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Score 4 Newer",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)) ?? .now,
            score: 4
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Score 4 Older",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)) ?? .now,
            score: 4
        )
        try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Score 2",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)) ?? .now,
            score: 2
        )

        let repo = LocalArticleRepository(modelContainer: container)
        let firstPage = await repo.listFeedPage(filter: ArticleFilter(), sort: .scoreDesc, cursor: nil, limit: 2)
        #expect(firstPage.map(\.title) == ["Score 5", "Score 4 Newer"])

        let cursor = try #require(
            firstPage.last.map {
                ArticleListCursor(
                    sortDate: $0.querySortDate,
                    articleID: $0.id,
                    displayedScore: $0.queryDisplayedScore
                )
            }
        )

        let secondPage = await repo.listFeedPage(filter: ArticleFilter(), sort: .scoreDesc, cursor: cursor, limit: 2)
        #expect(secondPage.map(\.title) == ["Score 4 Older", "Score 2"])
    }

    @Test("Feed page storage scope can return archived articles only")
    func feedPageArchivedScopeReturnsArchivedArticlesOnly() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context)
        let calendar = Calendar(identifier: .gregorian)

        let active = try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Active Story",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)) ?? .now,
            score: 4
        )
        let archived = try insertVisibleArticle(
            in: context,
            feed: feed,
            title: "Archived Story",
            publishedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 6)) ?? .now,
            score: 3
        )
        archived.archive(reason: .ageLimit, at: .now)
        active.refreshQueryState()
        archived.refreshQueryState()
        try context.save()

        let repo = LocalArticleRepository(modelContainer: container)

        var archivedFilter = ArticleFilter()
        archivedFilter.storageScope = .archived
        let archivedResults = await repo.listFeedPage(filter: archivedFilter, sort: .newest, cursor: nil, limit: 10)
        #expect(archivedResults.map(\.title) == ["Archived Story"])

        var activeFilter = ArticleFilter()
        activeFilter.storageScope = .active
        let activeResults = await repo.listFeedPage(filter: activeFilter, sort: .newest, cursor: nil, limit: 10)
        #expect(activeResults.map(\.title) == ["Active Story"])
    }

    @Test("Active article counts by feed ignore archived rows")
    func activeArticleCountsByFeedIgnoreArchivedRows() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context)

        for index in 0..<12 {
            let article = Article(canonicalUrl: "https://example.com/\(index)", title: "Article \(index)")
            article.feed = feed
            article.publishedAt = Date(timeIntervalSince1970: TimeInterval(index))
            article.markScorePrepared(revision: currentPersonalizationVersion)
            if index >= 10 {
                article.archive(reason: .feedLimit, at: .now)
            }
            context.insert(article)
        }
        try context.save()

        let repo = LocalArticleRepository(modelContainer: container)
        let counts = await repo.activeArticleCountsByFeed()
        #expect(counts[feed.id] == 10)
    }

}
