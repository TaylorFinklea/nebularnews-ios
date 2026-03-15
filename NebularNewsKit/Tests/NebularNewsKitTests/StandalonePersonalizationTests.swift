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

    @Test("Source profiles attach only a safe baseline tag when article text is generic")
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
        #expect(tagNames.contains("Artificial Intelligence"))
        #expect(tagNames.contains("Generative AI") == false)
        #expect(tagNames.contains("Large Language Models") == false)
        #expect(snapshot.systemTagIDs.count == 1)
    }

    @Test("Source-profile bonus tags require lexical article evidence")
    func sourceProfileBonusTagsRequireLexicalEvidence() async throws {
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
        let genericArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Platform update",
            canonicalURL: "https://example.com/openai-generic",
            content: "Release notes and availability changes.",
            publishedAt: .now
        )
        let lexicalArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT language models add generative AI workflows",
            canonicalURL: "https://example.com/openai-lexical",
            content: longContent("GPT language models and generative AI workflows keep improving."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let genericTags = Set(try fetchArticle(genericArticle.id, in: context).tags?.map(\.name) ?? [])
        let lexicalTags = Set(try fetchArticle(lexicalArticle.id, in: context).tags?.map(\.name) ?? [])

        #expect(genericTags.contains("Artificial Intelligence"))
        #expect(genericTags.contains("Generative AI") == false)
        #expect(genericTags.contains("Large Language Models") == false)

        #expect(lexicalTags.contains("Artificial Intelligence"))
        #expect(lexicalTags.contains("Generative AI"))
        #expect(lexicalTags.contains("Large Language Models"))
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
        #expect(mitTagNames.contains("Artificial Intelligence"))
        #expect(mitTagNames.contains("Research") == false)
        #expect(mitTagNames.contains("Large Language Models") == false)
        #expect(mitSnapshot.systemTagIDs.count == 1)

        let openAISnapshot = try #require(await service.debugSnapshot(articleID: openAIHostArticle.id))
        let openAITagNames = Set(openAISnapshot.currentTags.map(\.name))
        #expect(openAISnapshot.matchedSourceProfiles.contains("OpenAI News"))
        #expect(openAITagNames.contains("Artificial Intelligence"))
        #expect(openAITagNames.contains("Generative AI") == false)
        #expect(openAITagNames.contains("Large Language Models") == false)
        #expect(openAISnapshot.systemTagIDs.count == 1)
    }

    @Test("Mainstream starter source profiles attach the expected baseline tags")
    func mainstreamStarterSourceProfilesAttachBaselineTags() async throws {
        struct Case: Sendable {
            let feedTitle: String
            let feedURL: String
            let siteURL: String?
            let expectedTag: String
            let unexpectedBonus: String?
        }

        let cases: [Case] = [
            .init(
                feedTitle: "PBS NewsHour Headlines",
                feedURL: "https://www.pbs.org/newshour/feeds/rss/headlines",
                siteURL: "https://www.pbs.org/newshour",
                expectedTag: "World News",
                unexpectedBonus: "U.S. News"
            ),
            .init(
                feedTitle: "PBS NewsHour Politics",
                feedURL: "https://www.pbs.org/newshour/feeds/rss/politics",
                siteURL: "https://www.pbs.org/newshour/politics",
                expectedTag: "Politics",
                unexpectedBonus: "Policy"
            ),
            .init(
                feedTitle: "TechCrunch",
                feedURL: "https://techcrunch.com/feed/",
                siteURL: "https://techcrunch.com",
                expectedTag: "Consumer Tech",
                unexpectedBonus: "Startups"
            ),
            .init(
                feedTitle: "MedlinePlus Health News",
                feedURL: "https://medlineplus.gov/feeds/news_en.xml",
                siteURL: "https://medlineplus.gov",
                expectedTag: "Health",
                unexpectedBonus: "Medicine"
            ),
            .init(
                feedTitle: "ESPN Top Headlines",
                feedURL: "https://www.espn.com/espn/rss/news",
                siteURL: "https://www.espn.com",
                expectedTag: "Sports",
                unexpectedBonus: nil
            ),
            .init(
                feedTitle: "Smitten Kitchen",
                feedURL: "https://smittenkitchen.com/feed/",
                siteURL: "https://smittenkitchen.com",
                expectedTag: "Food",
                unexpectedBonus: "Recipes"
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
                title: "Top story",
                canonicalURL: "https://example.com/mainstream-\(index)",
                content: "General update without category-specific lexical evidence.",
                publishedAt: .now.addingTimeInterval(TimeInterval(index * 60))
            )
        }

        _ = await service.processPendingArticles(limit: 50)

        let articles = try context.fetch(FetchDescriptor<Article>())

        for article in articles {
            let item = try #require(cases.first(where: { $0.feedTitle == article.feed?.title }))
            let tagNames = Set((article.tags ?? []).map(\.name))
            #expect(tagNames.contains(item.expectedTag))
            if let unexpectedBonus = item.unexpectedBonus {
                #expect(tagNames.contains(unexpectedBonus) == false)
            }
        }
    }

    @Test("Broad starter keywords can attach new politics and food tags")
    func broadStarterKeywordsAttachNewTags() async throws {
        let container = try makeContainer()
        let service = LocalStandalonePersonalizationService(modelContainer: container)
        let context = makeContext(container)

        await service.bootstrap()
        let feed = try insertFeed(
            in: context,
            title: "General Digest",
            feedURL: "https://example.com/general.xml",
            siteURL: "https://example.com"
        )

        let politicsArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "White House campaign legislation update",
            canonicalURL: "https://example.com/politics-keywords",
            content: longContent("The White House campaign and legislation update covered government agencies and cabinet priorities."),
            publishedAt: .now
        )
        let foodArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Weeknight recipe to cook and bake at home",
            canonicalURL: "https://example.com/food-keywords",
            content: longContent("This recipe uses simple ingredients and kitchen prep to cook a great meal and bake dessert."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let politicsTags = Set(try fetchArticle(politicsArticle.id, in: context).tags?.map(\.name) ?? [])
        let foodTags = Set(try fetchArticle(foodArticle.id, in: context).tags?.map(\.name) ?? [])

        #expect(politicsTags.contains("Politics"))
        #expect(politicsTags.contains("Policy") || politicsTags.contains("Government"))
        #expect(foodTags.contains("Food"))
        #expect(foodTags.contains("Cooking") || foodTags.contains("Recipes"))
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
                expectedTags: ["Birding"]
            ),
            .init(
                feedTitle: "Nature Boost",
                feedURL: "https://example.com/nature-boost.xml",
                siteURL: nil,
                expectedTags: ["Nature"]
            ),
            .init(
                feedTitle: "Kansas City Today",
                feedURL: "https://www.kcur.org/podcast/kansas-city-today/rss.xml",
                siteURL: "https://www.kcur.org/podcast/kansas-city-today",
                expectedTags: ["Local News", "Kansas City"]
            ),
            .init(
                feedTitle: "Federal Reserve Bank of Kansas City publications",
                feedURL: "https://www.kansascityfed.org/rss/publications.xml",
                siteURL: "https://www.kansascityfed.org/research/",
                expectedTags: ["Economics"]
            ),
            .init(
                feedTitle: "NIST News",
                feedURL: "https://www.nist.gov/news-events/news/rss.xml",
                siteURL: "https://www.nist.gov/news-events/news",
                expectedTags: ["Standards"]
            ),
            .init(
                feedTitle: "Distill",
                feedURL: "https://distill.pub/rss.xml",
                siteURL: "https://distill.pub/",
                expectedTags: ["Research"]
            ),
            .init(
                feedTitle: "NVIDIA Blog",
                feedURL: "https://blogs.nvidia.com/feed/",
                siteURL: "https://blogs.nvidia.com/",
                expectedTags: ["Artificial Intelligence"]
            ),
            .init(
                feedTitle: "Cloud Native Computing Foundation",
                feedURL: "https://www.cncf.io/feed/",
                siteURL: "https://www.cncf.io/",
                expectedTags: ["Cloud Infrastructure"]
            ),
            .init(
                feedTitle: "Grafana Labs blog on Grafana Labs",
                feedURL: "https://grafana.com/blog/rss/",
                siteURL: "https://grafana.com/blog/",
                expectedTags: ["Observability"]
            ),
            .init(
                feedTitle: "Security on Grafana Labs",
                feedURL: "https://grafana.com/security/rss/",
                siteURL: "https://grafana.com/security/",
                expectedTags: ["Cybersecurity"]
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
            #expect(snapshot.systemTagIDs.count <= defaultDeterministicMaxSystemTags)
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

    @Test("Deterministic tagging never attaches more than three system tags")
    func deterministicTaggingRespectsHardSystemTagCap() async throws {
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
            title: "GPT, multimodal reasoning, AI agents, robotics, and cloud-native tooling",
            canonicalURL: "https://example.com/capped-tags",
            content: longContent("GPT multimodal reasoning, large language models, AI agents, robotics, Kubernetes, and cloud infrastructure all appear in the same story."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let stored = try fetchArticle(article.id, in: context)
        #expect(stored.systemTagIds.count <= defaultDeterministicMaxSystemTags)
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

        article.setReaction(value: 1, reasonCodes: ["up_interest_match", "up_author_like"])
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
        #expect(stored.reactionUpdatedAt != nil)
        #expect(topicRows.isEmpty == false)
        #expect(authorRows.count == 1)
        #expect(try context.fetch(FetchDescriptor<FeedAffinity>()).count == 1)
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
        storedA.setReaction(value: 1)
        try context.save()
        await service.processReactionChange(articleID: storedA.id, previousValue: nil, newValue: 1, reasonCodes: [])

        let storedB = try fetchArticle(articleB.id, in: context)
        storedB.setReaction(value: -1)
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
        reactedTracked.setReaction(value: 1)
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
        storedA.setReaction(value: 1)
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

    @Test("Source trust feedback becomes a data-backed source reputation signal after the first vote")
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
        let articleC = try insertArticle(
            in: context,
            feed: feed,
            title: "Third release",
            content: longContent("A third GPT update ships this week."),
            publishedAt: .now.addingTimeInterval(20),
            author: "Taylor"
        )

        _ = await service.processPendingArticles(limit: 20)
        let articleRepo = LocalArticleRepository(modelContainer: container)

        let storedA = try fetchArticle(articleA.id, in: context)
        storedA.setReaction(value: 1, reasonCodes: ["up_source_trust"])
        try context.save()
        try await articleRepo.syncStandaloneUserState(id: storedA.id)

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: ["up_source_trust"]
        )

        let afterFirstReaction = try fetchArticle(articleA.id, in: context)
        let initialSourceSignal = try #require(afterFirstReaction.signalScores.first(where: { $0.signal == .sourceReputation }))
        #expect(initialSourceSignal.rawValue > 0)

        let storedB = try fetchArticle(articleB.id, in: context)
        storedB.setReaction(value: 1, reasonCodes: ["up_source_trust"])
        try context.save()
        try await articleRepo.syncStandaloneUserState(id: storedB.id)

        let baselineC = try fetchArticle(articleC.id, in: context).scoreWeightedAverage ?? 0
        await service.processReactionChange(
            articleID: articleB.id,
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

        let rescoredC = try fetchArticle(articleC.id, in: context)
        let sourceSignal = try #require(rescoredC.signalScores.first(where: { $0.signal == .sourceReputation }))
        #expect(sourceSignal.rawValue > 0)
        #expect((rescoredC.scoreWeightedAverage ?? 0) != baselineC)
    }

    @Test("Negative topic learning creates negative topic-affinity scores for related articles")
    func negativeTopicLearningAffectsTopicAffinity() async throws {
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
        storedA.setReaction(value: -1, reasonCodes: ["down_off_topic"])
        try context.save()

        await service.processReactionChange(
            articleID: articleA.id,
            previousValue: nil,
            newValue: -1,
            reasonCodes: ["down_off_topic"]
        )

        let rescoredB = try fetchArticle(articleB.id, in: context)
        let topicSignal = try #require(rescoredB.signalScores.first(where: { $0.signal == .topicAffinity }))
        #expect(topicSignal.rawValue < 0)
        #expect(topicSignal.normalizedValue < 0.5)
        #expect((rescoredB.scoreWeightedAverage ?? 0) < baselineB)
    }

    @Test("Centered learning increases low-signal weights on downvotes and decreases them on upvotes")
    func centeredLearningAdjustsLowSignalsAroundNeutral() async throws {
        let downvoteContainer = try makeContainer()
        let downvoteService = LocalStandalonePersonalizationService(modelContainer: downvoteContainer)
        let downvoteContext = makeContext(downvoteContainer)

        await downvoteService.bootstrap()
        let downvoteFeed = try insertFeed(in: downvoteContext, title: "General Interest")
        let oldDownvoteArticle = try insertArticle(
            in: downvoteContext,
            feed: downvoteFeed,
            title: "Old archive story",
            canonicalURL: "https://example.com/old-downvote",
            content: longContent("A plain archive story with enough depth to produce structural signals."),
            publishedAt: .now.addingTimeInterval(-(24 * 3600 * 120))
        )

        _ = await downvoteService.processPendingArticles(limit: 10)
        let freshnessWeightBeforeDownvote = try fetchSignalWeight(.contentFreshness, in: downvoteContext).weight
        oldDownvoteArticle.setReaction(value: -1)
        try downvoteContext.save()

        await downvoteService.processReactionChange(
            articleID: oldDownvoteArticle.id,
            previousValue: nil,
            newValue: -1,
            reasonCodes: []
        )

        let freshnessWeightAfterDownvote = try fetchSignalWeight(.contentFreshness, in: downvoteContext).weight
        #expect(freshnessWeightAfterDownvote > freshnessWeightBeforeDownvote)

        let upvoteContainer = try makeContainer()
        let upvoteService = LocalStandalonePersonalizationService(modelContainer: upvoteContainer)
        let upvoteContext = makeContext(upvoteContainer)

        await upvoteService.bootstrap()
        let upvoteFeed = try insertFeed(in: upvoteContext, title: "General Interest")
        let oldUpvoteArticle = try insertArticle(
            in: upvoteContext,
            feed: upvoteFeed,
            title: "Old favorite story",
            canonicalURL: "https://example.com/old-upvote",
            content: longContent("A plain archive story with enough depth to produce structural signals."),
            publishedAt: .now.addingTimeInterval(-(24 * 3600 * 120))
        )

        _ = await upvoteService.processPendingArticles(limit: 10)
        let freshnessWeightBeforeUpvote = try fetchSignalWeight(.contentFreshness, in: upvoteContext).weight
        oldUpvoteArticle.setReaction(value: 1)
        try upvoteContext.save()

        await upvoteService.processReactionChange(
            articleID: oldUpvoteArticle.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: []
        )

        let freshnessWeightAfterUpvote = try fetchSignalWeight(.contentFreshness, in: upvoteContext).weight
        #expect(freshnessWeightAfterUpvote < freshnessWeightBeforeUpvote)
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
        storedA.setReaction(value: -1, reasonCodes: ["down_avoid_author"])
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
        reactedTracked.setReaction(value: 1)

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

    @Test("Historical replay rebuilds learned state from reactions and dismissals")
    func historicalReplayRebuildsLearnedState() async throws {
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

        let reactedArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "GPT reasoning improves workplace automation",
            canonicalURL: "https://example.com/replay-reaction",
            content: longContent("GPT reasoning improves workplace automation and author preference learning."),
            publishedAt: .now,
            author: "Riley"
        )
        reactedArticle.personalizationVersion = 5
        reactedArticle.setReaction(
            value: 1,
            reasonCodes: ["up_interest_match", "up_author_like"],
            at: Date(timeIntervalSince1970: 10)
        )

        let dismissedArticle = try insertArticle(
            in: context,
            feed: feed,
            title: "Older update to dismiss",
            canonicalURL: "https://example.com/replay-dismiss",
            content: longContent("A plain update from the same feed."),
            publishedAt: .now.addingTimeInterval(60)
        )
        dismissedArticle.personalizationVersion = 5
        dismissedArticle.markDismissed(at: Date(timeIntervalSince1970: 20))
        try context.save()

        let processed = await service.rebuildPersonalizationFromHistory(batchSize: 10, force: true)

        let feedKey = try #require(normalizedFeedKey(from: feed.feedUrl))
        let rebuiltReactedArticle = try fetchArticle(reactedArticle.id, in: context)
        let rebuiltDismissedArticle = try fetchArticle(dismissedArticle.id, in: context)
        let feedAffinity = try fetchFeedAffinity(feedKey, in: context)
        let topicRows = try context.fetch(FetchDescriptor<TopicAffinity>())
        let authorRows = try context.fetch(FetchDescriptor<AuthorAffinity>())
        let signalWeights = try context.fetch(FetchDescriptor<SignalWeight>())

        #expect(processed == 2)
        #expect(rebuiltReactedArticle.personalizationVersion == currentPersonalizationVersion)
        #expect(rebuiltDismissedArticle.personalizationVersion == currentPersonalizationVersion)
        #expect(feedAffinity.interactionCount == 2)
        #expect(topicRows.isEmpty == false)
        #expect(authorRows.count == 1)
        #expect(signalWeights.contains(where: { $0.sampleCount > 0 }))
    }

    @Test("Audit snapshot reports learned rows and over-tagged articles")
    func auditSnapshotReportsLearnedRowsAndOverTaggedArticles() async throws {
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
            title: "Audit target",
            canonicalURL: "https://example.com/audit-target",
            content: longContent("A plain briefing with enough depth to create structural signals."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        article.setReaction(value: 1, reasonCodes: ["up_interest_match"])
        article.markDismissed(at: Date(timeIntervalSince1970: 30))
        try context.save()

        await service.processReactionChange(
            articleID: article.id,
            previousValue: nil,
            newValue: 1,
            reasonCodes: ["up_interest_match"]
        )

        let firstFourTagIDs = try context.fetch(FetchDescriptor<NebularNewsKit.Tag>())
            .prefix(4)
            .map(\.id)
        article.systemTagIdsJson = String(
            data: try JSONEncoder().encode(firstFourTagIDs),
            encoding: .utf8
        )
        try context.save()

        let snapshot = await service.auditSnapshot()

        #expect(snapshot.reactedArticles == 1)
        #expect(snapshot.dismissedArticles == 1)
        #expect(snapshot.feedAffinityRows == 1)
        #expect(snapshot.signalWeightRows == SignalName.allCases.count)
        #expect(snapshot.overTaggedArticles == 1)
        #expect(snapshot.readyScoreHistogram.reduce(0) { $0 + $1.count } == snapshot.totalReadyScores)
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
