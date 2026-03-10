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

    @Test("Score preparation ignores AI suggestion and score-assist failures")
    func scorePreparationStaysDeterministic() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Deterministic Score Preparation",
            content: longContent("A detailed article body suitable for scoring."),
            imageURL: "https://example.com/image.jpg"
        )

        let service = ArticlePreparationService(
            modelContainer: container,
            generationCoordinator: ThrowingGenerationCoordinator()
        )
        let articleRepo = LocalArticleRepository(modelContainer: container)
        try await articleRepo.enqueueMissingProcessingJobs(for: article.id)

        let processed = await service.processPendingArticles(batchSize: 10, allowLowPriority: false)
        let stored = try #require(await articleRepo.get(id: article.id))
        let scoreJob = await articleRepo.processingJob(articleID: article.id, stage: .scoreAndTag)

        #expect(processed == 1)
        #expect(stored.isPresentationReady)
        #expect(stored.scorePreparedRevision >= currentPersonalizationVersion)
        #expect(scoreJob?.status == .done)
    }

    @Test("Hidden migrated articles are backfilled into score jobs on warm paths")
    func hiddenArticlesAreBackfilledIntoScoreJobs() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Migrated Hidden Article",
            content: longContent("A detailed article body suitable for scoring."),
            imageURL: "https://example.com/image.jpg"
        )

        article.scorePreparedRevision = currentPersonalizationVersion
        article.queryIsVisible = false
        article.presentationReadyAt = nil
        try context.save()

        let articleRepo = LocalArticleRepository(modelContainer: container)
        let backfilled = try await articleRepo.backfillMissingProcessingJobsForInvisibleArticles(limit: 10)
        let pending = await articleRepo.pendingVisibleArticleCount()
        let claimed = await articleRepo.claimProcessingJobs(limit: 10, allowLowPriority: false)

        #expect(backfilled == 1)
        #expect(pending == 1)
        #expect(claimed.contains(ArticleProcessingJob.makeKey(articleID: article.id, stage: .scoreAndTag)))
    }

    @Test("Pending visible count reflects active score jobs instead of all hidden rows")
    func pendingVisibleCountTracksActiveJobsOnly() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        _ = try insertArticle(
            in: context,
            feed: feed,
            title: "Hidden Without Job",
            content: longContent("A detailed article body suitable for scoring."),
            imageURL: "https://example.com/image.jpg"
        )

        let articleRepo = LocalArticleRepository(modelContainer: container)
        let pendingBefore = await articleRepo.pendingVisibleArticleCount()
        _ = try await articleRepo.backfillMissingProcessingJobsForInvisibleArticles(limit: 10)
        let pendingAfter = await articleRepo.pendingVisibleArticleCount()

        #expect(pendingBefore == 0)
        #expect(pendingAfter == 1)
    }

    @Test("Claiming jobs reclaims stale running score jobs for live hidden articles")
    func claimProcessingJobsReclaimsStaleRunningJobs() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Stale Running Job",
            content: longContent("A detailed article body suitable for scoring."),
            imageURL: "https://example.com/image.jpg"
        )

        let staleJob = ArticleProcessingJob(
            articleID: article.id,
            stage: .scoreAndTag,
            status: .running,
            priority: 300,
            inputRevision: max(article.contentRevision, currentPersonalizationVersion),
            updatedAt: Date().addingTimeInterval(-600)
        )
        context.insert(staleJob)
        try context.save()

        let articleRepo = LocalArticleRepository(modelContainer: container)
        let claimed = await articleRepo.claimProcessingJobs(limit: 10, allowLowPriority: false)
        let refreshed = await articleRepo.processingJob(articleID: article.id, stage: .scoreAndTag)

        #expect(claimed.contains(staleJob.key))
        #expect(refreshed?.status == .running)
    }

    @Test("Claiming jobs deletes orphaned processing rows")
    func claimProcessingJobsDeletesOrphans() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let orphanArticleID = UUID().uuidString
        let orphanJob = ArticleProcessingJob(
            articleID: orphanArticleID,
            stage: .scoreAndTag,
            status: .queued,
            priority: 300,
            inputRevision: currentPersonalizationVersion
        )
        context.insert(orphanJob)
        try context.save()

        let articleRepo = LocalArticleRepository(modelContainer: container)
        _ = await articleRepo.claimProcessingJobs(limit: 10, allowLowPriority: false)
        let stored = await articleRepo.processingJob(articleID: orphanArticleID, stage: .scoreAndTag)

        #expect(stored == nil)
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

private actor ThrowingGenerationCoordinator: AIGenerationCoordinating {
    func isFoundationModelsAvailable() async -> Bool {
        true
    }

    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget
    ) async throws -> SummaryGenerationOutput? {
        throw PreparationCoordinatorError.unexpectedInvocation
    }

    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput? {
        throw PreparationCoordinatorError.unexpectedInvocation
    }

    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput? {
        throw PreparationCoordinatorError.unexpectedInvocation
    }
}

private enum PreparationCoordinatorError: Error {
    case unexpectedInvocation
}
