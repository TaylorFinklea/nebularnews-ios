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

    private func fetchFeedAffinity(_ feedKey: String, in context: ModelContext) throws -> FeedAffinity {
        let descriptor = FetchDescriptor<FeedAffinity>(
            predicate: #Predicate<FeedAffinity> { $0.feedKey == feedKey }
        )
        return try #require(context.fetch(descriptor).first)
    }

#if DEBUG
    private func coverageRow(
        named familyName: String,
        in snapshots: [TargetFeedCoverageSnapshot]
    ) throws -> TargetFeedCoverageSnapshot {
        try #require(snapshots.first(where: { $0.familyName == familyName }))
    }
#endif

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

    @Test("Source profiles match normalized feed-title aliases and host aliases")
    func sourceProfilesMatchNormalizedAliasesAndHosts() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let mitFeed = try insertFeed(
            in: context,
            title: " Artificial intelligence   -   MIT Technology Review ",
            feedURL: "https://www.technologyreview.com/topic/artificial-intelligence/rss.xml"
        )
        let mitArticle = try insertArticle(
            in: context,
            feed: mitFeed,
            title: "Weekly briefing",
            content: "A short update without article-level keywords.",
            publishedAt: .now
        )

        let openAIHostFeed = try insertFeed(
            in: context,
            title: "Lab Notes",
            feedURL: "https://example.com/openai.xml",
            siteURL: "https://www.openai.com/news"
        )
        let openAIHostArticle = try insertArticle(
            in: context,
            feed: openAIHostFeed,
            title: "Platform changes",
            content: "Release notes and availability changes.",
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let mitSnapshot = try #require(await service.debugSnapshot(articleID: mitArticle.id))
        let mitTagNames = Set(mitSnapshot.currentTags.map(\.name))
        #expect(mitSnapshot.matchedSourceProfiles.contains("Artificial intelligence – MIT Technology Review"))
        #expect(mitTagNames.isSuperset(of: ["Artificial Intelligence", "Research", "Large Language Models"]))

        let openAISnapshot = try #require(await service.debugSnapshot(articleID: openAIHostArticle.id))
        let openAITagNames = Set(openAISnapshot.currentTags.map(\.name))
        #expect(openAISnapshot.matchedSourceProfiles.contains("OpenAI News"))
        #expect(openAITagNames.isSuperset(of: ["Artificial Intelligence", "Generative AI", "Large Language Models"]))
    }

    @Test("The Berkeley AI Research feed gets tags from its source profile")
    func berkeleyAIResearchFeedGetsProfileTags() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "The Berkeley Artificial Intelligence Research Blog",
            feedURL: "https://bair.berkeley.edu/blog/feed.xml",
            siteURL: "https://bair.berkeley.edu/blog/"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Lab update",
            content: "Announcements from the lab.",
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let snapshot = try #require(await service.debugSnapshot(articleID: article.id))
        let tagNames = Set(snapshot.currentTags.map(\.name))

        #expect(snapshot.matchedSourceProfiles.contains("The Berkeley Artificial Intelligence Research Blog"))
        #expect(tagNames.isSuperset(of: ["Artificial Intelligence", "Research"]))
        #expect(snapshot.systemTagIDs.count == 2)
    }

    @Test("Expanded source profiles cover the current mixed-feed corpus")
    func expandedSourceProfilesCoverCurrentCorpus() async throws {
        struct Case: Sendable {
            let feedTitle: String
            let feedURL: String
            let siteURL: String?
            let expectedTags: Set<String>
        }

        let cases: [Case] = [
            .init(
                feedTitle: "The American Birding Podcast",
                feedURL: "https://www.aba.org/feed/",
                siteURL: "https://www.aba.org/",
                expectedTags: ["Birding", "Wildlife", "Conservation", "Nature"]
            ),
            .init(
                feedTitle: "Nature Boost",
                feedURL: "https://example.com/nature-boost.xml",
                siteURL: nil,
                expectedTags: ["Wildlife", "Conservation", "Nature"]
            ),
            .init(
                feedTitle: "Kansas City Today",
                feedURL: "https://www.kcur.org/podcast/kansas-city-today/rss.xml",
                siteURL: "https://www.kcur.org/podcast/kansas-city-today",
                expectedTags: ["Local News", "Kansas City", "Civics"]
            ),
            .init(
                feedTitle: "Federal Reserve Bank of Kansas City publications",
                feedURL: "https://www.kansascityfed.org/rss/publications.xml",
                siteURL: "https://www.kansascityfed.org/research/",
                expectedTags: ["Economics", "Monetary Policy", "Inflation", "Banking"]
            ),
            .init(
                feedTitle: "NIST News",
                feedURL: "https://www.nist.gov/news-events/news/rss.xml",
                siteURL: "https://www.nist.gov/news-events/news",
                expectedTags: ["Standards", "Research"]
            ),
            .init(
                feedTitle: "Distill",
                feedURL: "https://distill.pub/rss.xml",
                siteURL: "https://distill.pub/",
                expectedTags: ["Research", "Artificial Intelligence", "Deep Learning"]
            ),
            .init(
                feedTitle: "NVIDIA Blog",
                feedURL: "https://blogs.nvidia.com/feed/",
                siteURL: "https://blogs.nvidia.com/",
                expectedTags: ["Artificial Intelligence", "GPUs", "Semiconductors", "Data Centers"]
            ),
            .init(
                feedTitle: "Cloud Native Computing Foundation",
                feedURL: "https://www.cncf.io/feed/",
                siteURL: "https://www.cncf.io/",
                expectedTags: ["Cloud Infrastructure", "Kubernetes", "Open Source"]
            ),
            .init(
                feedTitle: "Grafana Labs blog on Grafana Labs",
                feedURL: "https://grafana.com/blog/rss/",
                siteURL: "https://grafana.com/blog/",
                expectedTags: ["Observability", "Open Source", "Developer Tools"]
            ),
            .init(
                feedTitle: "Security on Grafana Labs",
                feedURL: "https://grafana.com/security/rss/",
                siteURL: "https://grafana.com/security/",
                expectedTags: ["Cybersecurity", "Observability", "Developer Tools"]
            )
        ]

        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()

        for (index, item) in cases.enumerated() {
            let feed = try insertFeed(
                in: context,
                title: item.feedTitle,
                feedURL: item.feedURL,
                siteURL: item.siteURL
            )
            _ = try insertArticle(
                in: context,
                feed: feed,
                title: "Profile coverage \(index)",
                canonicalURL: "https://example.com/profile-\(index)",
                content: "Generic update without extra article-level keywords.",
                publishedAt: .now.addingTimeInterval(Double(index))
            )
        }

        _ = await service.processPendingArticles(limit: 50)

        for item in cases {
            let articles = try context.fetch(FetchDescriptor<Article>())
            let article = try #require(articles.first(where: { $0.feed?.title == item.feedTitle }))
            let snapshot = try #require(await service.debugSnapshot(articleID: article.id))
            let tagNames = Set(snapshot.currentTags.map(\.name))
            #expect(tagNames.isSuperset(of: item.expectedTags))
        }
    }

    @Test("Expanded keywords classify civic, economic, and observability language")
    func expandedKeywordsClassifyNewDomains() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "General Interest")

        let civicArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "City council considers zoning changes to bus fare policy",
            canonicalURL: "https://example.com/civics",
            content: longContent("The city council and mayor debated transit access, zoning, and rent pressure."),
            publishedAt: .now
        )
        let economicsArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Labor market wages and inflation expectations after interest rate moves",
            canonicalURL: "https://example.com/economics",
            content: longContent("Economists tracked inflation expectations, labor market wages, and monetary policy."),
            publishedAt: .now.addingTimeInterval(60)
        )
        let observabilityArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Improving observability with metrics, logs, tracing, and SLOs",
            canonicalURL: "https://example.com/observability",
            content: longContent("Teams used observability, tracing, metrics, and incident response playbooks for SRE."),
            publishedAt: .now.addingTimeInterval(120)
        )

        _ = await service.processPendingArticles(limit: 20)

        let civicTags = Set(try fetchArticle(civicArticle.id, in: context).tags?.map(\.name) ?? [])
        #expect(civicTags.isSuperset(of: ["Civics", "Transportation", "Housing"]))

        let economicsTags = Set(try fetchArticle(economicsArticle.id, in: context).tags?.map(\.name) ?? [])
        #expect(economicsTags.isSuperset(of: ["Economics", "Monetary Policy", "Inflation"]))

        let observabilityTags = Set(try fetchArticle(observabilityArticle.id, in: context).tags?.map(\.name) ?? [])
        #expect(observabilityTags.isSuperset(of: ["Observability", "Site Reliability"]))
    }

    @Test("Birding tracking stories no longer get privacy tags")
    func birdingTrackingStoriesAvoidPrivacyFalsePositives() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "Nature Boost",
            feedURL: "https://example.com/nature-boost.xml"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Tracking Snowy Owls in Missouri",
            canonicalURL: "https://example.com/snowy-owls",
            content: longContent("Wildlife teams track owl habitat and species migration patterns in nature preserves."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let tagNames = Set(try fetchArticle(article.id, in: context).tags?.map(\.name) ?? [])
        #expect(tagNames.contains("Privacy") == false)
        #expect(tagNames.isSuperset(of: ["Wildlife", "Nature"]))
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

    @Test("Dismiss, undismiss, read, and unread keep passive state separate")
    func passiveStateTransitionsStaySeparate() {
        let article = Article(canonicalUrl: "https://example.com/article", title: "Passive state")

        article.markDismissed(at: Date(timeIntervalSince1970: 10))
        #expect(article.isDismissed)
        #expect(article.isRead == false)
        #expect(article.isUnreadQueueCandidate == false)

        article.clearDismissal()
        #expect(article.isDismissed == false)
        #expect(article.isUnreadQueueCandidate)

        article.markRead(at: Date(timeIntervalSince1970: 20))
        #expect(article.isRead)
        #expect(article.isDismissed == false)
        #expect(article.isUnreadQueueCandidate == false)

        article.markUnread()
        #expect(article.isRead == false)
        #expect(article.isDismissed == false)
        #expect(article.isUnreadQueueCandidate)
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

    @Test("Feed affinity keys normalize from feed URLs instead of local feed identity")
    func feedAffinityUsesNormalizedFeedURLKeys() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let firstFeed = try insertFeed(
            in: context,
            title: "First title",
            feedURL: "HTTPS://WWW.EXAMPLE.COM/News/Feed.XML/?utm_source=test",
            siteURL: "https://example.com/news"
        )
        let secondFeed = try insertFeed(
            in: context,
            title: "Second title",
            feedURL: "https://example.com/news/feed.xml#latest",
            siteURL: "https://example.com/news"
        )

        let articleA = try insertArticle(
            in: context,
            feed: firstFeed,
            title: "First reaction target",
            canonicalURL: "https://example.com/article-a",
            content: longContent("Generic briefing with enough words for depth."),
            publishedAt: .now
        )
        let articleB = try insertArticle(
            in: context,
            feed: secondFeed,
            title: "Second reaction target",
            canonicalURL: "https://example.com/article-b",
            content: longContent("Another generic briefing with enough words for depth."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let normalizedKey = try #require(normalizedFeedKey(from: firstFeed.feedUrl))

        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.reactionValue = 1
        try context.save()
        await service.processReactionChange(articleID: storedA.id, previousValue: nil, newValue: 1, reasonCodes: [])

        let storedB = try fetchArticle(articleB.id, in: context)
        storedB.reactionValue = -1
        try context.save()
        await service.processReactionChange(articleID: storedB.id, previousValue: nil, newValue: -1, reasonCodes: [])

        let feedAffinities = try context.fetch(FetchDescriptor<FeedAffinity>())
        let affinity = try fetchFeedAffinity(normalizedKey, in: context)

        #expect(feedAffinities.count == 1)
        #expect(affinity.interactionCount == 2)
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

    @Test("Stale selection prioritizes reacted tracked tech articles before unrelated backlog")
    func staleSelectionPrioritizesReactedTrackedTechArticles() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let trackedFeed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let otherFeed = try insertFeed(in: context, title: "General Interest")

        let reactedTracked = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "GPT release reaction target",
            content: longContent("GPT reasoning model notes."),
            publishedAt: .now.addingTimeInterval(-600)
        )
        reactedTracked.reactionValue = 1
        reactedTracked.fetchedAt = Date(timeIntervalSince1970: 1)

        let tracked = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "OpenAI backlog item",
            content: longContent("Generic OpenAI platform update."),
            publishedAt: .now.addingTimeInterval(-300)
        )
        tracked.fetchedAt = Date(timeIntervalSince1970: 2)

        let other = try insertArticle(
            in: context,
            feed: otherFeed,
            title: "Newest unrelated backlog item",
            content: longContent("A general news roundup."),
            publishedAt: .now
        )
        other.fetchedAt = Date(timeIntervalSince1970: 3)
        try context.save()

        let processed = await service.processPendingArticles(limit: 2)

        let storedReactedTracked = try fetchArticle(reactedTracked.id, in: context)
        let storedTracked = try fetchArticle(tracked.id, in: context)
        let storedOther = try fetchArticle(other.id, in: context)

        #expect(processed == 2)
        #expect(storedReactedTracked.personalizationVersion == currentPersonalizationVersion)
        #expect(storedTracked.personalizationVersion == currentPersonalizationVersion)
        #expect(storedOther.personalizationVersion < currentPersonalizationVersion)
    }

    @Test("Feed affinity makes sparse-tag same-feed articles ready after a reaction")
    func feedAffinityMakesSparseTagArticlesReady() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "General Interest",
            feedURL: "https://example.com/general.xml"
        )
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "Generic industry briefing",
            canonicalURL: "https://example.com/general-a",
            content: longContent("A plain briefing with enough depth to create structural signals."),
            publishedAt: .now
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "Second generic briefing",
            canonicalURL: "https://example.com/general-b",
            content: longContent("Another plain briefing with enough depth to create structural signals."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let baselineB = try fetchArticle(articleB.id, in: context)
        #expect(baselineB.tags?.isEmpty != false)
        #expect(baselineB.scoreStatus == LocalScoreStatus.insufficientSignal.rawValue)

        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.reactionValue = 1
        try context.save()

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: []
        )

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let feedSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .feedAffinity }))

        #expect(feedSignal.rawValue > 0)
        #expect(rescoredB.scoreStatus == LocalScoreStatus.ready.rawValue)
        #expect(rescoredB.score != nil)
    }

    @Test("Dismissing an article lowers feed affinity without changing source trust")
    func dismissingArticleLowersFeedAffinityOnly() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "General Interest",
            feedURL: "https://example.com/general.xml"
        )
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Dismiss target",
            canonicalURL: "https://example.com/dismiss-target",
            content: longContent("A plain briefing with enough depth to create structural signals."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let sourceWeightBefore = try fetchSignalWeight(.sourceReputation, in: context)
        let previousDismissedAt = article.dismissedAt
        article.markDismissed()
        try context.save()

        await service.processDismissChange(
            articleID: article.id,
            previousDismissedAt: previousDismissedAt,
            newDismissedAt: article.dismissedAt
        )

        let feedKey = try #require(normalizedFeedKey(from: feed.feedUrl))
        let feedAffinity = try fetchFeedAffinity(feedKey, in: context)
        let sourceWeightAfter = try fetchSignalWeight(.sourceReputation, in: context)

        #expect(feedAffinity.affinity < 0)
        #expect(sourceWeightAfter.sampleCount == sourceWeightBefore.sampleCount)
        #expect(sourceWeightAfter.weight == sourceWeightBefore.weight)
    }

    @Test("Dismiss rescoring propagates to the same feed")
    func dismissRescoringPropagatesToSameFeed() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "General Interest",
            feedURL: "https://example.com/general.xml"
        )
        let articleA = try insertArticle(
            in: context,
            feed: feed,
            title: "Dismiss target",
            canonicalURL: "https://example.com/dismiss-a",
            content: longContent("A plain briefing with enough depth to create structural signals."),
            publishedAt: .now
        )
        let articleB = try insertArticle(
            in: context,
            feed: feed,
            title: "Same feed neighbor",
            canonicalURL: "https://example.com/dismiss-b",
            content: longContent("Another plain briefing with enough depth to create structural signals."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let baselineB = try fetchArticle(articleB.id, in: context).scoreWeightedAverage ?? 0
        let previousDismissedAt = articleA.dismissedAt
        articleA.markDismissed()
        try context.save()

        await service.processDismissChange(
            articleID: articleA.id,
            previousDismissedAt: previousDismissedAt,
            newDismissedAt: articleA.dismissedAt
        )

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let feedSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .feedAffinity }))

        #expect(feedSignal.rawValue < 0)
        #expect((rescoredB.scoreWeightedAverage ?? 0) < baselineB)
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
        #expect((rescoredB.scoreWeightedAverage ?? 0) != baselineB)
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

#if DEBUG
    @Test("Target-family reprocess drains target-family stale items only")
    func targetFamilyReprocessDrainsTargetFamilyStaleItemsOnly() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let trackedFeed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let otherFeed = try insertFeed(in: context, title: "General Interest")

        let trackedA = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "Tracked item one",
            content: longContent("GPT release notes."),
            publishedAt: .now
        )
        let trackedB = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "Tracked item two",
            content: longContent("Another GPT update."),
            publishedAt: .now.addingTimeInterval(60)
        )
        let other = try insertArticle(
            in: context,
            feed: otherFeed,
            title: "Other backlog item",
            content: longContent("General news roundup."),
            publishedAt: .now.addingTimeInterval(120)
        )

        let processed = await service.reprocessTargetFeedFamilies(batchSize: 1)

        let storedTrackedA = try fetchArticle(trackedA.id, in: context)
        let storedTrackedB = try fetchArticle(trackedB.id, in: context)
        let storedOther = try fetchArticle(other.id, in: context)

        #expect(processed == 2)
        #expect(storedTrackedA.personalizationVersion == currentPersonalizationVersion)
        #expect(storedTrackedB.personalizationVersion == currentPersonalizationVersion)
        #expect(storedOther.personalizationVersion < currentPersonalizationVersion)
    }

    @Test("Target-family coverage snapshot reports per-family counts")
    func targetFeedCoverageSnapshotReportsPerFeedCounts() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let trackedFeed = try insertFeed(
            in: context,
            title: "OpenAI News",
            feedURL: "https://openai.com/blog/rss.xml",
            siteURL: "https://openai.com/news"
        )
        let otherFeed = try insertFeed(in: context, title: "General Interest")

        let reactedTracked = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "Reacted tracked article",
            content: longContent("GPT reasoning model release notes."),
            publishedAt: .now
        )
        reactedTracked.reactionValue = 1

        let dismissedTracked = try insertArticle(
            in: context,
            feed: trackedFeed,
            title: "Stale tracked article",
            content: longContent("Another OpenAI update."),
            publishedAt: .now.addingTimeInterval(60)
        )
        dismissedTracked.markDismissed(at: Date(timeIntervalSince1970: 30))

        _ = try insertArticle(
            in: context,
            feed: otherFeed,
            title: "Untracked article",
            content: longContent("General news roundup."),
            publishedAt: .now.addingTimeInterval(120)
        )
        try context.save()

        _ = await service.processPendingArticles(limit: 1)

        let snapshots = await service.targetFeedCoverageSnapshot()
        let openAI = try coverageRow(named: "OpenAI News", in: snapshots)

        #expect(openAI.total == 2)
        #expect(openAI.currentVersion == 1)
        #expect(openAI.systemTagged == 1)
        #expect(openAI.readyScored == 0)
        #expect(openAI.reacted == 1)
        #expect(openAI.dismissed == 1)
    }
#endif

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
