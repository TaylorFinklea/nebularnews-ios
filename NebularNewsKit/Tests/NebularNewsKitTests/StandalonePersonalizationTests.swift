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

    private func longContent(_ phrase: String, repeating count: Int = 220) -> String {
        Array(repeating: phrase, count: count).joined(separator: " ")
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

    @Test("Source profiles attach mapped tags even when article text is generic")
    func sourceProfilesAttachMappedTags() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Platform update",
            content: "Release notes and availability changes.",
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let snapshot = try #require(await service.debugSnapshot(articleID: article.id))
        let tagNames = Set(snapshot.currentTags.map(\.name))

        #expect(snapshot.matchedSourceProfiles.contains("OpenAI News"))
        #expect(tagNames.isSuperset(of: ["Artificial Intelligence", "Generative AI", "Large Language Models"]))
        #expect(snapshot.systemTagIDs.count == 3)
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

    @Test("Missing local preference data keeps the article in learning with sparse signals")
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
        #expect(stored.signalScores.isEmpty)
        #expect(abs((stored.scoreWeightedAverage ?? 0) - 0.5) < 0.0001)
    }

    @Test("Reaction before personalization creates tags, affinities, and a same-flow score refresh")
    func reactionBeforePersonalizationCreatesTagsAndRows() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT improvements for everyday work",
            content: longContent("GPT reasoning model improvements help teams collaborate better."),
            publishedAt: .now,
            author: "Sam"
        )

        article.reactionValue = 1
        article.reactionReasonCodes = "up_interest_match,up_author_like"
        try context.save()

        await service.processReactionChange(
            articleID: article.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: ["up_interest_match", "up_author_like"]
        )

        let stored = try fetchArticle(article.id, in: context)
        let topicRows = try context.fetch(FetchDescriptor<TopicAffinity>())
        let authorRows = try context.fetch(FetchDescriptor<AuthorAffinity>())

        #expect(stored.personalizationVersion == currentPersonalizationVersion)
        #expect(stored.scoreStatus != nil)
        #expect(stored.signalScores.isEmpty == false)
        #expect(stored.systemTagIds.isEmpty == false)
        #expect(topicRows.isEmpty == false)
        #expect(authorRows.count == 1)
    }

    @Test("Version-based backlog processing skips current-version articles")
    func versionBasedBacklogProcessingSkipsCurrentVersionArticles() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let currentArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Already current",
            content: longContent("Generic platform update."),
            publishedAt: .now.addingTimeInterval(-60)
        )
        currentArticle.personalizationVersion = currentPersonalizationVersion
        try context.save()

        let staleArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Needs backfill",
            content: longContent("GPT release notes and API usage."),
            publishedAt: .now
        )

        let processed = await service.processPendingArticles(limit: 10)

        let storedCurrent = try fetchArticle(currentArticle.id, in: context)
        let storedStale = try fetchArticle(staleArticle.id, in: context)

        #expect(processed == 1)
        #expect(storedCurrent.personalizationVersion == currentPersonalizationVersion)
        #expect(storedCurrent.systemTagIds.isEmpty)
        #expect(storedStale.personalizationVersion == currentPersonalizationVersion)
        #expect(storedStale.systemTagIds.isEmpty == false)
    }

    @Test("Source trust learning targets source reputation and rescored cohort articles in the same feed")
    func sourceTrustLearningTargetsSourceReputation() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT ships new reasoning mode",
            content: longContent("GPT reasoning model ships with better tool use."),
            publishedAt: .now,
            author: "Taylor"
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "Second release",
            content: longContent("Another GPT update ships this week."),
            publishedAt: .now.addingTimeInterval(10),
            author: "Taylor"
        )

        _ = await service.processPendingArticles(limit: 10)

        let baselineB = try fetchArticle(articleB.id, in: context).scoreWeightedAverage ?? 0
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
        let sourceSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .sourceReputation }))
        #expect(sourceSignal.rawValue > 0)
        #expect((rescoredB.scoreWeightedAverage ?? 0) > baselineB)
    }

    @Test("Negative topic learning creates negative tag-match scores for related articles")
    func negativeTopicLearningAffectsTagMatchRatio() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT agents expand into healthcare",
            content: longContent("Artificial intelligence agents continue expanding into healthcare workflows."),
            publishedAt: .now
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT agents expand again",
            content: longContent("Artificial intelligence agents continue expanding into enterprise workflows."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 10)

        let baselineB = try fetchArticle(articleB.id, in: context).scoreWeightedAverage ?? 0
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

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let tagMatchSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .tagMatchRatio }))
        #expect(tagMatchSignal.rawValue < 0)
        #expect(tagMatchSignal.normalizedValue < 0.5)
        #expect((rescoredB.scoreWeightedAverage ?? 0) < baselineB)
    }

    @Test("Author learning propagates to related articles by the same author")
    func authorLearningRescoresSameAuthorCohort() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "The latest research from Google",
            feedURL: "https://research.google/blog/rss/",
            siteURL: "https://research.google/blog/"
        )
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "Gemini advances reasoning",
            content: longContent("Gemini reasoning model research improves multimodal reasoning."),
            publishedAt: .now,
            author: "Riley Chen"
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "Gemini research update",
            content: longContent("Gemini research continues exploring reasoning models."),
            publishedAt: .now.addingTimeInterval(60),
            author: "Riley Chen"
        )

        _ = await service.processPendingArticles(limit: 10)

        let baselineB = try fetchArticle(articleB.id, in: context).scoreWeightedAverage ?? 0
        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.reactionValue = -1
        storedA.reactionReasonCodes = "down_avoid_author"
        try context.save()

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: -1,
            reasonCodes: ["down_avoid_author"]
        )

        let authorRows = try context.fetch(FetchDescriptor<AuthorAffinity>())
        let rescoredB = try fetchArticle(articleB.id, in: context)
        let authorSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .authorAffinity }))

        #expect(authorRows.count == 1)
        #expect(authorSignal.rawValue < 0)
        #expect((rescoredB.scoreWeightedAverage ?? 0) < baselineB)
    }

    @Test("Score band thresholds use the new fixed ranges")
    func scoreBandThresholds() {
        let cases: [(Double, Int)] = [
            (0.00, 1),
            (0.21, 1),
            (0.22, 2),
            (0.39, 2),
            (0.40, 3),
            (0.57, 3),
            (0.58, 4),
            (0.75, 4),
            (0.76, 5),
            (1.00, 5)
        ]

        for (weightedAverage, expectedScore) in cases {
            #expect(scoreBand(for: weightedAverage) == expectedScore)
        }
    }
}
