import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("OnboardingSeedService")
struct OnboardingSeedServiceTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @Test("Starter feed choices preselect at most two defaults per interest and cap defaults at twelve")
    func starterFeedChoiceCap() throws {
        let selected = Set(starterInterestCatalog.map(\.id))
        let choices = buildStarterFeedChoices(
            selectedInterestIDs: selected,
            avoidedInterestIDs: [],
            maximumDefaultsPerInterest: 2,
            maximumSelectedFeeds: 12
        )

        let selectedChoices = choices.filter(\.isInitiallySelected)

        #expect(selectedChoices.count == 12)

        for interest in starterInterestCatalog {
            let interestSelectedCount = selectedChoices.reduce(into: 0) { count, choice in
                if choice.interestIDs.contains(interest.id) {
                    count += 1
                }
            }
            #expect(interestSelectedCount <= 2)
        }
    }

    @Test("Popular and more interest sections use the intended catalog order")
    func starterInterestSectionsMatchProductOrder() {
        #expect(popularStarterInterestIDs == [
            "world-us-news",
            "consumer-tech",
            "ai-ml",
            "health-wellness",
            "sports",
            "food-cooking"
        ])
        #expect(moreStarterInterestIDs == [
            "politics-policy",
            "research-deep-dives",
            "cloud-devops",
            "security-privacy",
            "space-science",
            "nature-wildlife",
            "photography",
            "economics-policy"
        ])
        #expect(Set(popularStarterInterestIDs).isDisjoint(with: Set(moreStarterInterestIDs)))
        #expect(popularStarterInterestIDs.count + moreStarterInterestIDs.count == starterInterestCatalog.count)
    }

    @Test("New mainstream interests resolve the expected starter feed bundle")
    func mainstreamInterestBundlesMatchCatalog() throws {
        let expectations: [(String, [String])] = [
            ("world-us-news", ["pbs-newshour-headlines", "bbc-world-news"]),
            ("consumer-tech", ["ars-technica", "techcrunch"]),
            ("health-wellness", ["medlineplus-health-news", "medlineplus-health-topics"]),
            ("sports", ["espn-top-headlines"]),
            ("food-cooking", ["smitten-kitchen"]),
            ("politics-policy", ["pbs-newshour-politics", "bbc-politics"])
        ]

        for (interestID, expectedFeedIDs) in expectations {
            let choices = buildStarterFeedChoices(
                selectedInterestIDs: Set([interestID]),
                avoidedInterestIDs: []
            )

            #expect(choices.map(\.feed.id) == expectedFeedIDs)
        }
    }

    @Test("Imported feeds dedupe against canonical starter feeds")
    func importedFeedsDedupeAgainstStarterCatalog() throws {
        let imported = try #require(
            StarterFeedDefinition.custom(
                title: "OpenAI Legacy",
                feedURL: "https://openai.com/blog/rss.xml"
            )
        )

        let choices = buildStarterFeedChoices(
            selectedInterestIDs: Set(["ai-ml"]),
            avoidedInterestIDs: [],
            customFeeds: [imported]
        )

        let openAIChoices = choices.filter { $0.feed.feedURL == "https://openai.com/news/rss.xml" }

        #expect(openAIChoices.count == 1)
        #expect(choices.count == 5)
    }

    @Test("Avoided interests remove their starter feeds from the review bundle")
    func avoidedInterestsRemoveStarterFeeds() throws {
        let choices = buildStarterFeedChoices(
            selectedInterestIDs: Set(["ai-ml"]),
            avoidedInterestIDs: Set(["ai-ml"])
        )

        #expect(choices.isEmpty)
    }

    @Test("Onboarding seeding inserts feeds and writes topic and feed affinities only")
    func onboardingSeedingWritesExpectedRows() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let existingFeed = Feed(feedUrl: "https://openai.com/blog/rss.xml", title: "")
        existingFeed.isEnabled = false
        context.insert(existingFeed)
        try context.save()

        let service = OnboardingSeedService(modelContainer: container)
        let request = OnboardingSeedRequest(
            selectedInterestIDs: ["ai-ml", "cloud-devops"],
            avoidedInterestIDs: ["nature-wildlife"],
            selectedFeeds: [
                try #require(starterFeed(id: "openai-news")),
                try #require(starterFeed(id: "deepmind-news")),
                try #require(starterFeed(id: "cncf"))
            ]
        )

        let result = try await service.apply(request: request)

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let topicRows = (try? context.fetch(FetchDescriptor<TopicAffinity>())) ?? []
        let feedRows = (try? context.fetch(FetchDescriptor<FeedAffinity>())) ?? []
        let syncedFeeds = (try? context.fetch(FetchDescriptor<SyncedFeedSubscription>())) ?? []
        let authorRows = (try? context.fetch(FetchDescriptor<AuthorAffinity>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<SignalWeight>())) ?? []

        let resolvedOpenAI = try #require(feeds.first(where: { canonicalStarterFeedURL($0.feedUrl) == "https://openai.com/news/rss.xml" }))
        let aiTopic = try #require(topicRows.first(where: { $0.tagNameNormalized == "artificial intelligence" }))
        let natureTopic = try #require(topicRows.first(where: { $0.tagNameNormalized == "nature" }))
        let openAIFeedAffinity = try #require(feedRows.first(where: { $0.feedKey == normalizedFeedKey(from: resolvedOpenAI.feedUrl) }))

        #expect(result.feedIDs.count == 3)
        #expect(resolvedOpenAI.isEnabled)
        #expect(aiTopic.affinity == 0.6)
        #expect(natureTopic.affinity == -0.6)
        #expect(openAIFeedAffinity.affinity == 0.35)
        #expect(syncedFeeds.count == 3)
        #expect(authorRows.isEmpty)
        #expect(weights.count == defaultSignalWeights.count)
    }

    @Test("Mainstream onboarding interests seed new topic and feed affinities")
    func onboardingSeedingWritesMainstreamInterestSeeds() async throws {
        let container = try makeContainer()
        let context = makeContext(container)

        let service = OnboardingSeedService(modelContainer: container)
        let request = OnboardingSeedRequest(
            selectedInterestIDs: ["world-us-news", "health-wellness"],
            avoidedInterestIDs: ["food-cooking"],
            selectedFeeds: [
                try #require(starterFeed(id: "pbs-newshour-headlines")),
                try #require(starterFeed(id: "medlineplus-health-news"))
            ]
        )

        _ = try await service.apply(request: request)

        let topicRows = (try? context.fetch(FetchDescriptor<TopicAffinity>())) ?? []
        let feedRows = (try? context.fetch(FetchDescriptor<FeedAffinity>())) ?? []

        let worldNews = try #require(topicRows.first(where: { $0.tagNameNormalized == "world news" }))
        let health = try #require(topicRows.first(where: { $0.tagNameNormalized == "health" }))
        let food = try #require(topicRows.first(where: { $0.tagNameNormalized == "food" }))
        let pbsFeed = try #require(feedRows.first(where: { $0.feedKey == normalizedFeedKey(from: "https://www.pbs.org/newshour/feeds/rss/headlines") }))

        #expect(worldNews.affinity == 0.6)
        #expect(health.affinity == 0.6)
        #expect(food.affinity == -0.6)
        #expect(pbsFeed.affinity == 0.35)
    }
}
