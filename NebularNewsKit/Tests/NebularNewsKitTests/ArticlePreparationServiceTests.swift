import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("ArticlePreparationService")
struct ArticlePreparationServiceTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @discardableResult
    private func insertFeed(
        in context: ModelContext,
        title: String,
        feedURL: String = "https://example.com/feed.xml"
    ) throws -> Feed {
        let feed = Feed(feedUrl: feedURL, title: title)
        context.insert(feed)
        try context.save()
        return feed
    }

    @discardableResult
    private func insertArticle(
        in context: ModelContext,
        feed: Feed,
        title: String,
        canonicalURL: String = "https://example.com/article",
        content: String? = nil,
        imageURL: String? = nil
    ) throws -> Article {
        let article = Article(canonicalUrl: canonicalURL, title: title)
        article.feed = feed
        article.contentHtml = content
        article.imageUrl = imageURL
        article.contentHash = UUID().uuidString
        article.contentRevision = 1
        article.contentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        if let content, !content.isEmpty {
            article.contentPreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        }
        if imageURL != nil {
            article.imagePreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue
            article.imagePreparedRevision = currentImagePreparationRevision
        }
        article.refreshQueryState()
        context.insert(article)
        try context.save()
        return article
    }

    private func longContent(_ phrase: String, repeating count: Int = 220) -> String {
        Array(repeating: phrase, count: count).joined(separator: " ")
    }

    @Test("Newly inserted articles stay hidden until presentation stages are attempted")
    func newArticlesRemainHiddenUntilPrepared() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        _ = try insertArticle(
            in: context,
            feed: feed,
            title: "Pending Article",
            content: nil,
            imageURL: nil
        )

        let articleRepo = LocalArticleRepository(modelContainer: container)
        let visibleCount = await articleRepo.countVisibleArticles(filter: ArticleFilter())

        var pendingFilter = ArticleFilter()
        pendingFilter.presentationFilter = .pendingOnly
        let pendingCount = await articleRepo.count(filter: pendingFilter)

        #expect(visibleCount == 0)
        #expect(pendingCount == 1)
    }

    @Test("Articles become visible after score preparation even when other attempts fail")
    func scoredArticlesBecomeVisibleWithoutSuccessfulLowPriorityStages() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Attempted Article",
            content: nil,
            imageURL: nil
        )

        article.contentPreparationStatusRaw = ArticlePreparationStageStatus.failed.rawValue
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.blocked.rawValue
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        article.markScorePrepared(revision: currentPersonalizationVersion)
        try context.save()

        let articleRepo = LocalArticleRepository(modelContainer: container)
        let visibleCount = await articleRepo.countVisibleArticles(filter: ArticleFilter())
        let stored = await articleRepo.get(id: article.id)

        #expect(visibleCount == 1)
        #expect(stored?.isPresentationReady == true)
        #expect(stored?.presentationReadyAt != nil)
    }

    @Test("No-provider enrichment is skipped and still unblocks article visibility")
    func noProviderEnrichmentMarksSkipped() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Prepared Article",
            content: longContent("A detailed article body suitable for summarization."),
            imageURL: "https://example.com/image.jpg"
        )

        let service = ArticlePreparationService(
            modelContainer: container,
            generationCoordinator: PreparationMockGenerationCoordinator(summaryOutput: nil)
        )
        let articleRepo = LocalArticleRepository(modelContainer: container)
        try await articleRepo.enqueueMissingProcessingJobs(for: article.id)

        let processed = await service.processPendingArticles(batchSize: 10)
        let stored = try #require(await articleRepo.get(id: article.id))

        #expect(processed == 2)
        #expect(stored.contentPreparationStatusValue == .skipped)
        #expect(stored.imagePreparationStatusValue == .succeeded)
        #expect(stored.enrichmentPreparationStatusValue == .skipped)
        #expect(stored.isPresentationReady)
        #expect(stored.presentationReadyAt != nil)
    }
}

private actor PreparationMockGenerationCoordinator: AIGenerationCoordinating {
    let summaryOutput: SummaryGenerationOutput?

    init(summaryOutput: SummaryGenerationOutput?) {
        self.summaryOutput = summaryOutput
    }

    func isFoundationModelsAvailable() async -> Bool {
        false
    }

    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget
    ) async throws -> SummaryGenerationOutput? {
        summaryOutput
    }

    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput? {
        nil
    }

    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput? {
        nil
    }
}
