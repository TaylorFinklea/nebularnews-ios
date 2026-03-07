import Foundation
import SwiftData
import Testing
@testable import NebularNewsKit

@Suite("StandalonePersonalization")
struct StandalonePersonalizationTests {
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
        feedURL: String = "https://example.com/feed.xml",
        siteURL: String? = nil
    ) throws -> Feed {
        let feed = Feed(feedUrl: feedURL, title: title)
        feed.siteUrl = siteURL
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
        excerpt: String? = nil,
        publishedAt: Date? = nil,
        author: String? = nil
    ) throws -> Article {
        let article = Article(canonicalUrl: canonicalURL, title: title)
        article.feed = feed
        article.contentHtml = content
        article.excerpt = excerpt
        article.publishedAt = publishedAt
        article.author = author
        context.insert(article)
        try context.save()
        return article
    }

    private func fetchArticle(_ articleID: String, in context: ModelContext) throws -> Article {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == articleID }
        )
        return try #require(context.fetch(descriptor).first)
    }

    private func fetchTag(named name: String, in context: ModelContext) throws -> NebularNewsKit.Tag {
        let descriptor = FetchDescriptor<NebularNewsKit.Tag>()
        let tags = try context.fetch(descriptor)
        return try #require(tags.first(where: { $0.name == name }))
    }

    private func fetchSignalWeight(_ signal: SignalName, in context: ModelContext) throws -> SignalWeight {
        let descriptor = FetchDescriptor<SignalWeight>(
            predicate: #Predicate<SignalWeight> { $0.signalName == signal.rawValue }
        )
        return try #require(context.fetch(descriptor).first)
    }

    @Test("Starter canonical taxonomy is seeded once and stays canonical")
    func starterCanonicalTaxonomyIsSeededIdempotently() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        await service.bootstrap()

        let tags = try context.fetch(FetchDescriptor<NebularNewsKit.Tag>())
        #expect(tags.count == starterCanonicalTags.count)
        #expect(tags.filter { $0.isCanonical }.count == starterCanonicalTags.count)
        #expect(Set(tags.map(\.slug)).count == starterCanonicalTags.count)
    }

    @Test("Deterministic tagging uses feed title and hostname signals")
    func deterministicTaggingUsesFeedTitleAndHostname() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "Kubernetes Weekly",
            siteURL: "https://developer-tools.example.com"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "CLI roundup",
            content: "A short update without explicit tags in the title.",
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let stored = try fetchArticle(article.id, in: context)
        let tagNames = Set((stored.tags ?? []).map(\.name))

        #expect(tagNames.contains("Kubernetes"))
        #expect(tagNames.contains("Developer Tools"))
        #expect(stored.systemTagIds.count >= 2)
    }

    @Test("Manual tags survive system tagging and are not marked as system-managed")
    func manualTagsSurviveSystemTagging() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let roboticsTag = try fetchTag(named: "Robotics", in: context)
        let feed = try insertFeed(in: context, title: "Automation")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "LLM agents assist warehouse teams",
            content: "Agentic tooling and foundation model orchestration now guide robots in warehouses.",
            publishedAt: .now
        )
        article.tags = [roboticsTag]
        try context.save()

        _ = await service.processPendingArticles(limit: 10)

        let stored = try fetchArticle(article.id, in: context)
        let tagNames = Set((stored.tags ?? []).map(\.name))

        #expect(tagNames.contains("Robotics"))
        #expect(tagNames.contains("AI Agents"))
        #expect(stored.systemTagIds.contains(roboticsTag.id) == false)
    }

    @Test("Missing local preference data produces learning state with neutral missing signals")
    func missingPreferenceDataProducesLearningState() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "General")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Untitled note",
            content: nil,
            excerpt: nil,
            publishedAt: nil
        )

        _ = await service.processPendingArticles(limit: 10)

        let stored = try fetchArticle(article.id, in: context)
        #expect(stored.scoreStatus == LocalScoreStatus.insufficientSignal.rawValue)
        #expect(stored.score == nil)

        let bySignal = Dictionary(uniqueKeysWithValues: stored.signalScores.map { ($0.signal, $0) })
        #expect(bySignal[.contentDepth]?.normalizedValue == 0.5)
        #expect(bySignal[.contentDepth]?.isDataBacked == false)
        #expect(bySignal[.tagMatchRatio]?.normalizedValue == 0.5)
        #expect(bySignal[.tagMatchRatio]?.isDataBacked == false)
    }

    @Test("Source trust learning targets source reputation and skips topic and author affinity tables")
    func sourceTrustLearningTargetsSourceReputation() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "AI Daily")
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "LLM agents ship to production",
            content: "AI agents and large language models are shipping quickly.",
            publishedAt: .now,
            author: "Taylor"
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "Second release",
            content: "Another large language model update ships this week.",
            publishedAt: .now.addingTimeInterval(10),
            author: "Taylor"
        )

        _ = await service.processPendingArticles(limit: 10)

        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.reactionValue = 1
        storedA.reactionReasonCodes = "up_source_trust"
        try context.save()

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: ["up_source_trust"]
        )
        try await service.rescoreArticle(articleID: articleB.id)

        let sourceWeight = try fetchSignalWeight(.sourceReputation, in: context)
        let topicWeight = try fetchSignalWeight(.topicAffinity, in: context)
        let sourceDelta = sourceWeight.weight - (defaultSignalWeights[.sourceReputation] ?? 0)
        let topicDelta = topicWeight.weight - (defaultSignalWeights[.topicAffinity] ?? 0)

        #expect(sourceWeight.sampleCount > 0)
        #expect(sourceDelta > 0)
        #expect(sourceDelta > topicDelta)
        #expect(try context.fetch(FetchDescriptor<TopicAffinity>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AuthorAffinity>()).isEmpty)

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let sourceSignal = rescoredB.signalScores.first(where: { $0.signal == .sourceReputation })
        #expect(try #require(sourceSignal).rawValue > 0)
    }

    @Test("Negative topic learning makes tag-match ratio reduce future scores")
    func negativeTopicLearningAffectsTagMatchRatio() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "AI Daily")
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "AI agents launch in healthcare",
            content: "AI agents and artificial intelligence products are expanding fast.",
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.reactionValue = -1
        storedA.reactionReasonCodes = "down_off_topic"
        try context.save()

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: -1,
            reasonCodes: ["down_off_topic"]
        )

        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "AI agents expand again",
            content: "Artificial intelligence agents continue expanding into enterprise workflows.",
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 10)

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let tagMatchSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .tagMatchRatio }))
        #expect(tagMatchSignal.rawValue < 0)
        #expect(tagMatchSignal.normalizedValue < 0.5)
    }
}
