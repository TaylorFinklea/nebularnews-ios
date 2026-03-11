import Foundation
import SwiftData
import Testing
@testable import NebularNewsKit

@Suite("AIFeatures")
struct AIFeaturesTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @discardableResult
    private func insertSettings(
        in context: ModelContext,
        configure: (AppSettings) -> Void
    ) throws -> AppSettings {
        let settings = AppSettings()
        configure(settings)
        context.insert(settings)
        try context.save()
        return settings
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
        publishedAt: Date? = nil
    ) throws -> Article {
        let article = Article(canonicalUrl: canonicalURL, title: title)
        article.feed = feed
        article.contentHtml = content
        article.publishedAt = publishedAt
        context.insert(article)
        try context.save()
        return article
    }

    @discardableResult
    private func insertTag(
        in context: ModelContext,
        name: String,
        isCanonical: Bool
    ) throws -> NebularNewsKit.Tag {
        let tag = NebularNewsKit.Tag(name: name, isCanonical: isCanonical)
        context.insert(tag)
        try context.save()
        return tag
    }

    private func fetchArticle(_ articleID: String, in context: ModelContext) throws -> Article {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == articleID }
        )
        return try #require(context.fetch(descriptor).first)
    }

    private func fetchSuggestions(articleID: String, in context: ModelContext) throws -> [ArticleTagSuggestion] {
        let descriptor = FetchDescriptor<ArticleTagSuggestion>(
            predicate: #Predicate<ArticleTagSuggestion> { $0.articleId == articleID }
        )
        return try context.fetch(descriptor)
    }

    private func longContent(_ phrase: String, repeating count: Int = 220) -> String {
        Array(repeating: phrase, count: count).joined(separator: " ")
    }

    private var sampleSnapshot: ArticleSnapshot {
        ArticleSnapshot(
            id: "article-1",
            title: "Sample article",
            contentText: longContent("A deep article about AI and infrastructure."),
            canonicalUrl: "https://example.com/articles/1",
            feedTitle: "Sample Feed"
        )
    }

    private var sampleTagInput: TagSuggestionInput {
        TagSuggestionInput(
            articleID: "article-1",
            title: "Sample article",
            canonicalURL: "https://example.com/articles/1",
            contentText: longContent("A detailed article about supply chains and regulation."),
            feedTitle: "Sample Feed",
            siteHostname: "example.com",
            attachedTags: [],
            existingCandidates: [
                ExistingTagSuggestionCandidate(id: "ai", name: "Artificial Intelligence", matchScore: 0.72, articleCount: 12)
            ],
            maxSuggestions: 2
        )
    }

    @Test("Automatic summaries use Foundation Models first when available")
    func automaticSummariesPreferFoundationModels() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.automaticAIMode = .onDevice
        }

        let foundationRecorder = EngineRecorder()
        let anthropicRecorder = EngineRecorder()
        let openAIRecorder = EngineRecorder()

        let coordinator = AIGenerationCoordinator(
            modelContainer: container,
            keychainService: "tests.\(UUID().uuidString)",
            foundationModelsEngine: MockArticleGenerationEngine(
                provider: .foundationModels,
                modelIdentifier: "system",
                available: true,
                recorder: foundationRecorder
            ),
            anthropicFactory: { _, _ in
                MockArticleGenerationEngine(
                    provider: .anthropic,
                    modelIdentifier: "claude-test",
                    available: true,
                    recorder: anthropicRecorder
                )
            },
            openAIFactory: { _, _ in
                MockArticleGenerationEngine(
                    provider: .openAI,
                    modelIdentifier: "gpt-test",
                    available: true,
                    recorder: openAIRecorder
                )
            }
        )

        let output = try await coordinator.generateSummary(
            snapshot: sampleSnapshot,
            summaryStyle: "concise",
            target: .automatic
        )

        #expect(output?.provider == .foundationModels)
        #expect(await foundationRecorder.summaryCallCount() == 1)
        #expect(await anthropicRecorder.summaryCallCount() == 0)
        #expect(await openAIRecorder.summaryCallCount() == 0)
    }

    @Test("Automatic summaries stay disabled when automatic AI is off")
    func automaticSummariesDoNotFallbackWhenDisabled() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.automaticAIMode = .disabled
        }

        let coordinator = AIGenerationCoordinator(
            modelContainer: container,
            keychainService: "tests.\(UUID().uuidString)",
            foundationModelsEngine: MockArticleGenerationEngine(
                provider: .foundationModels,
                modelIdentifier: "system",
                available: false,
                recorder: EngineRecorder()
            )
        )

        let output = try await coordinator.generateSummary(
            snapshot: sampleSnapshot,
            summaryStyle: "concise",
            target: .automatic
        )

        #expect(output == nil)
    }

    @Test("Automatic summaries use Anthropic when LLM mode is selected")
    func automaticSummariesUseAnthropicWhenConfigured() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.automaticAIMode = .anthropicLLM
            settings.defaultModel = "claude-haiku-4-5-20251001"
        }

        let keychainService = "tests.\(UUID().uuidString)"
        let keychain = KeychainManager(service: keychainService)
        try keychain.set("anthropic-test-key", forKey: KeychainManager.Key.anthropicApiKey)
        defer { keychain.delete(forKey: KeychainManager.Key.anthropicApiKey) }

        let anthropicRecorder = EngineRecorder()
        let openAIRecorder = EngineRecorder()

        let coordinator = AIGenerationCoordinator(
            modelContainer: container,
            keychainService: keychainService,
            foundationModelsEngine: MockArticleGenerationEngine(
                provider: .foundationModels,
                modelIdentifier: "system",
                available: false,
                recorder: EngineRecorder()
            ),
            anthropicFactory: { _, _ in
                MockArticleGenerationEngine(
                    provider: .anthropic,
                    modelIdentifier: "claude-test",
                    available: true,
                    recorder: anthropicRecorder
                )
            },
            openAIFactory: { _, _ in
                MockArticleGenerationEngine(
                    provider: .openAI,
                    modelIdentifier: "gpt-4o-mini",
                    available: true,
                    recorder: openAIRecorder
                )
            }
        )

        let output = try await coordinator.generateSummary(
            snapshot: sampleSnapshot,
            summaryStyle: "concise",
            target: .automatic
        )

        #expect(output?.provider == .anthropic)
        #expect(await anthropicRecorder.summaryCallCount() == 1)
        #expect(await openAIRecorder.summaryCallCount() == 0)
    }

    @Test("On-device enrichment stores summary provenance metadata")
    func enrichmentStoresSummaryProvenance() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Sample Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Summary target",
            canonicalURL: "https://example.com/summary-target",
            content: longContent("A deep article about AI and infrastructure."),
            publishedAt: .now
        )

        let coordinator = MockGenerationCoordinator(
            summaryOutput: SummaryGenerationOutput(
                cardSummary: "A one-sentence card summary.",
                summary: "A compact but complete paragraph summary for the article.",
                keyPoints: ["Point 1", "Point 2", "Point 3", "Point 4"],
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = AIEnrichmentService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        let result = await service.enrichArticle(
            snapshot: ArticleSnapshot(
                id: article.id,
                title: article.title,
                contentText: longContent("A deep article about AI and infrastructure."),
                canonicalUrl: article.canonicalUrl,
                feedTitle: feed.title
            ),
            summaryStyle: "concise"
        )

        let stored = try fetchArticle(article.id, in: context)
        #expect(result.succeeded)
        #expect(stored.cardSummaryText == "A one-sentence card summary.")
        #expect(stored.summaryText == "A compact but complete paragraph summary for the article.")
        #expect(stored.summaryProvider == AIGenerationProvider.foundationModels.rawValue)
        #expect(stored.summaryModel == "system")
        #expect(stored.keyPoints.count == 4)
    }

    @Test("Suggestion generation stores only filtered suggestions and never auto-creates tags")
    func suggestionGenerationStoresFilteredSuggestionsOnly() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: MockGenerationCoordinator(
                tagSuggestionOutput: TagSuggestionOutput(
                    suggestions: [
                        SuggestedTagCandidate(name: "News", confidence: 0.99),
                        SuggestedTagCandidate(name: "Regional Desk", confidence: 0.99),
                        SuggestedTagCandidate(name: "Artificial Intelligence", confidence: 0.99),
                        SuggestedTagCandidate(name: "Foster Care", confidence: 0.93),
                        SuggestedTagCandidate(name: "Family Stability", confidence: 0.95),
                        SuggestedTagCandidate(name: "Weak Idea", confidence: 0.40)
                    ],
                    provider: .foundationModels,
                    modelIdentifier: "system"
                )
            )
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "Regional Desk")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "How one family navigated a fragile support system",
            canonicalURL: "https://example.com/family-support-system",
            content: longContent("This article covers foster care placements, adoption support, and family stability programs."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let suggestions = try fetchSuggestions(articleID: article.id, in: context)
            .filter { $0.dismissedAt == nil }
            .sorted { $0.name < $1.name }
        let names = suggestions.map(\.name)
        let tags = try context.fetch(FetchDescriptor<NebularNewsKit.Tag>())

        #expect(names == ["Family Stability", "Foster Care"])
        #expect(tags.count == starterCanonicalTags.count)
        #expect(suggestions.allSatisfy { $0.sourceProvider == AIGenerationProvider.foundationModels.rawValue })
        #expect(suggestions.allSatisfy { $0.sourceModel == "system" })
    }

    @Test("Articles with two strong existing candidates skip new suggestion generation")
    func strongExistingCandidatesSkipSuggestionGeneration() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let coordinator = MockGenerationCoordinator(
            tagSuggestionOutput: TagSuggestionOutput(
                suggestions: [
                    SuggestedTagCandidate(name: "Invented Topic", confidence: 0.99)
                ],
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "AI Weekly")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Artificial Intelligence and Generative AI deployment patterns",
            canonicalURL: "https://example.com/ai-deployment",
            content: longContent("Artificial intelligence and generative AI deployment patterns reshape product teams."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let suggestions = try fetchSuggestions(articleID: article.id, in: context)
        let stored = try fetchArticle(article.id, in: context)
        let tagNames = Set((stored.tags ?? []).map(\.name))

        #expect(await coordinator.tagSuggestionCallCount() == 0)
        #expect(suggestions.isEmpty)
        #expect(tagNames.contains("Artificial Intelligence"))
        #expect(tagNames.contains("Generative AI"))
    }

    @Test("Second suggestion requires higher confidence and near-duplicates are rejected")
    func strictSuggestionFilteringRejectsWeakSecondSuggestionsAndDuplicates() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: MockGenerationCoordinator(
                tagSuggestionOutput: TagSuggestionOutput(
                    suggestions: [
                        SuggestedTagCandidate(name: "Foster Care", confidence: 0.92),
                        SuggestedTagCandidate(name: "Foster Care Support", confidence: 0.99),
                        SuggestedTagCandidate(name: "Family Stability", confidence: 0.94),
                        SuggestedTagCandidate(name: "Regional Desk", confidence: 0.99)
                    ],
                    provider: .foundationModels,
                    modelIdentifier: "system"
                )
            )
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "Regional Desk")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "How one family navigated a fragile support system",
            canonicalURL: "https://example.com/family-support-system",
            content: longContent("This article covers foster care placements, adoption support, and family stability programs."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        let suggestions = try fetchSuggestions(articleID: article.id, in: context)
            .filter { $0.dismissedAt == nil }
            .sorted { $0.name < $1.name }

        #expect(suggestions.map(\.name) == ["Foster Care"])
    }

    @Test("Unavailable suggestion providers do not wipe previously stored suggestions")
    func unavailableSuggestionProviderDoesNotClearStoredSuggestions() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Regional Desk")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "How one family navigated a fragile support system",
            canonicalURL: "https://example.com/family-support-system",
            content: longContent("This article covers foster care placements, adoption support, and family stability programs."),
            publishedAt: .now
        )
        context.insert(
            ArticleTagSuggestion(
                articleId: article.id,
                name: "Foster Care",
                confidence: 0.91,
                sourceProvider: AIGenerationProvider.foundationModels.rawValue,
                sourceModel: "system"
            )
        )
        try context.save()

        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: MockGenerationCoordinator(tagSuggestionOutput: nil)
        )

        await service.bootstrap()
        _ = await service.processPendingArticles(limit: 10)

        let suggestions = try fetchSuggestions(articleID: article.id, in: context)
        #expect(suggestions.contains(where: { $0.name == "Foster Care" && $0.dismissedAt == nil }))
    }

    @Test("Accepting and dismissing suggestions create one non-canonical tag and suppress dismissed reruns")
    func acceptingAndDismissingSuggestionsBehaveCorrectly() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let coordinator = MockGenerationCoordinator(
            tagSuggestionOutput: TagSuggestionOutput(
                suggestions: [
                    SuggestedTagCandidate(name: "Foster Care", confidence: 0.93),
                    SuggestedTagCandidate(name: "Family Stability", confidence: 0.95)
                ],
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "Regional Desk")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "How one family navigated a fragile support system",
            canonicalURL: "https://example.com/family-support-system",
            content: longContent("This article covers foster care placements, adoption support, and family stability programs."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)

        var activeSuggestions = try fetchSuggestions(articleID: article.id, in: context)
            .filter { $0.dismissedAt == nil }
            .sorted { $0.name < $1.name }
        let accepted = try #require(activeSuggestions.first(where: { $0.name == "Foster Care" }))
        let dismissed = try #require(activeSuggestions.first(where: { $0.name == "Family Stability" }))

        await service.acceptTagSuggestion(articleID: article.id, suggestionID: accepted.id)
        await service.dismissTagSuggestion(articleID: article.id, suggestionID: dismissed.id)

        let storedAfterActions = try fetchArticle(article.id, in: context)
        let tags = try context.fetch(FetchDescriptor<NebularNewsKit.Tag>())
        let createdTag = try #require(tags.first(where: { $0.name == "Foster Care" }))
        #expect(createdTag.isCanonical == false)
        #expect((storedAfterActions.tags ?? []).contains(where: { $0.id == createdTag.id }))

        storedAfterActions.personalizationVersion = 0
        try context.save()
        _ = await service.processPendingArticles(limit: 10)

        activeSuggestions = try fetchSuggestions(articleID: article.id, in: context)
            .filter { $0.dismissedAt == nil }
            .sorted { $0.name < $1.name }
        #expect(activeSuggestions.isEmpty)

        let allSuggestions = try fetchSuggestions(articleID: article.id, in: context)
        #expect(allSuggestions.contains(where: { $0.name == "Family Stability" && $0.dismissedAt != nil }))
    }

    @Test("Accepted provisional tags are reusable existing candidates but never auto-attached deterministically")
    func acceptedProvisionalTagsAreReusableOnlyInAIMatchingLane() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: MockGenerationCoordinator(tagSuggestionOutput: nil)
        )
        let repository = LocalPersonalizationRepository(modelContainer: container)

        await service.bootstrap()
        let provisionalTag = try insertTag(in: context, name: "Foster Care", isCanonical: false)

        let firstFeed = try insertFeed(in: context, title: "General Interest")
        let taggedArticle = try insertArticle(
            in: context,
            feed: firstFeed,
            title: "Seed article",
            canonicalURL: "https://example.com/seed-article",
            content: longContent("A seed article about foster care policy and adoption."),
            publishedAt: .now
        )
        taggedArticle.tags = [provisionalTag]
        taggedArticle.personalizationVersion = 999
        try context.save()

        let secondFeed = try insertFeed(in: context, title: "General Interest", feedURL: "https://example.com/other.xml")
        let underfitArticle = try insertArticle(
            in: context,
            feed: secondFeed,
            title: "A local case study",
            canonicalURL: "https://example.com/foster-care-case-study",
            content: longContent("This local case study covers foster care outcomes and adoption support systems."),
            publishedAt: .now.addingTimeInterval(60)
        )

        _ = await service.processPendingArticles(limit: 20)

        let candidates = await repository.rankedExistingTagSuggestionCandidates(
            title: underfitArticle.title,
            contentText: longContent("This local case study covers foster care outcomes and adoption support systems."),
            limit: 20
        )
        let stored = try fetchArticle(underfitArticle.id, in: context)
        let tagNames = Set((stored.tags ?? []).map(\.name))

        #expect(candidates.contains(where: { $0.name == "Foster Care" && $0.isCanonical == false }))
        #expect(tagNames.contains("Foster Care") == false)
    }

    @Test("Explain-only score assist stores explanation without changing the displayed score")
    func explainOnlyScoreAssistKeepsDisplayedScore() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.scoreAssistMode = .explainOnly
        }

        let coordinator = MockGenerationCoordinator(
            scoreAssistOutput: ScoreAssistOutput(
                explanation: "The article is timely and lines up with learned interests.",
                adjustment: 1,
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "General Interest", feedURL: "https://example.com/general.xml")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Explain-only target",
            canonicalURL: "https://example.com/explain-only",
            content: longContent("A detailed article that creates enough structural signals."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)
        article.reactionValue = 1
        try context.save()

        await service.processReactionChange(articleID: article.id, previousValue: nil, newValue: 1, reasonCodes: [])

        let stored = try fetchArticle(article.id, in: context)
        let algorithmicScore = try #require(stored.score)
        #expect(stored.hasReadyScore)
        #expect(stored.scoreAssistExplanation == "The article is timely and lines up with learned interests.")
        #expect(stored.scoreAssistAdjustment == 0)
        #expect(stored.displayedScore == algorithmicScore)
        #expect(await coordinator.scoreAssistCallCount() == 1)
    }

    @Test("Algorithmic-only mode skips score assist generation and keeps the baseline score authoritative")
    func algorithmicOnlyModeSkipsScoreAssist() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.scoreAssistMode = .algorithmicOnly
        }

        let coordinator = MockGenerationCoordinator(
            scoreAssistOutput: ScoreAssistOutput(
                explanation: "This should not be used.",
                adjustment: 1,
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "General Interest", feedURL: "https://example.com/general.xml")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Algorithmic-only target",
            canonicalURL: "https://example.com/algorithmic-only",
            content: longContent("A detailed article that creates enough structural signals."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)
        article.reactionValue = 1
        try context.save()

        await service.processReactionChange(articleID: article.id, previousValue: nil, newValue: 1, reasonCodes: [])

        let stored = try fetchArticle(article.id, in: context)
        #expect(stored.hasReadyScore)
        #expect(stored.scoreAssistExplanation == nil)
        #expect(stored.scoreAssistAdjustment == nil)
        #expect(stored.displayedScore == stored.score)
        #expect(await coordinator.scoreAssistCallCount() == 0)
    }

    @Test("Hybrid score assist stores a bounded overlay without mutating the algorithmic baseline")
    func hybridScoreAssistAppliesOverlay() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        _ = try insertSettings(in: context) { settings in
            settings.scoreAssistMode = .hybridAdjust
        }

        let coordinator = MockGenerationCoordinator(
            scoreAssistOutput: ScoreAssistOutput(
                explanation: "The article fits current interests slightly better than the baseline suggests.",
                adjustment: 1,
                provider: .foundationModels,
                modelIdentifier: "system"
            )
        )
        let service = LocalStandalonePersonalizationService(
            modelContainer: container,
            generationCoordinator: coordinator
        )

        await service.bootstrap()
        let feed = try insertFeed(in: context, title: "General Interest", feedURL: "https://example.com/general.xml")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Hybrid target",
            canonicalURL: "https://example.com/hybrid-target",
            content: longContent("A detailed article that creates enough structural signals."),
            publishedAt: .now
        )

        _ = await service.processPendingArticles(limit: 10)
        article.reactionValue = 1
        try context.save()

        await service.processReactionChange(articleID: article.id, previousValue: nil, newValue: 1, reasonCodes: [])

        let stored = try fetchArticle(article.id, in: context)
        let algorithmicScore = try #require(stored.score)
        #expect(stored.hasReadyScore)
        #expect(stored.scoreAssistAdjustment == 1)
        #expect(stored.scoreAssistExplanation == "The article fits current interests slightly better than the baseline suggests.")
        #expect(stored.score == algorithmicScore)
        #expect(stored.displayedScore == min(5, algorithmicScore + 1))
        #expect(await coordinator.scoreAssistCallCount() == 1)
    }
}

private actor EngineRecorder {
    private var summaryCalls = 0
    private var tagSuggestionCalls = 0
    private var scoreAssistCalls = 0

    func recordSummaryCall() {
        summaryCalls += 1
    }

    func recordTagSuggestionCall() {
        tagSuggestionCalls += 1
    }

    func recordScoreAssistCall() {
        scoreAssistCalls += 1
    }

    func summaryCallCount() -> Int {
        summaryCalls
    }

    func tagSuggestionCallCount() -> Int {
        tagSuggestionCalls
    }

    func scoreAssistCallCount() -> Int {
        scoreAssistCalls
    }
}

private struct MockArticleGenerationEngine: ArticleGenerationEngine {
    let provider: AIGenerationProvider
    let modelIdentifier: String?
    let available: Bool
    let recorder: EngineRecorder

    func isAvailable() async -> Bool {
        available
    }

    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String
    ) async throws -> SummaryGenerationOutput {
        await recorder.recordSummaryCall()
        return SummaryGenerationOutput(
            cardSummary: "Mock card summary.",
            summary: "Mock paragraph summary.",
            keyPoints: ["One", "Two", "Three", "Four"],
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput {
        await recorder.recordTagSuggestionCall()
        return TagSuggestionOutput(
            suggestions: [],
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput {
        await recorder.recordScoreAssistCall()
        return ScoreAssistOutput(
            explanation: "Mock explanation",
            adjustment: 0,
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }
}

private actor MockGenerationCoordinator: AIGenerationCoordinating {
    private(set) var summaryCalls = 0
    private(set) var tagSuggestionCalls = 0
    private(set) var scoreAssistCalls = 0
    private var mostRecentTagSuggestionInput: TagSuggestionInput?

    let foundationModelsAvailable: Bool
    let summaryOutput: SummaryGenerationOutput?
    let tagSuggestionOutput: TagSuggestionOutput?
    let scoreAssistOutput: ScoreAssistOutput?

    init(
        foundationModelsAvailable: Bool = true,
        summaryOutput: SummaryGenerationOutput? = nil,
        tagSuggestionOutput: TagSuggestionOutput? = nil,
        scoreAssistOutput: ScoreAssistOutput? = nil
    ) {
        self.foundationModelsAvailable = foundationModelsAvailable
        self.summaryOutput = summaryOutput
        self.tagSuggestionOutput = tagSuggestionOutput
        self.scoreAssistOutput = scoreAssistOutput
    }

    func isFoundationModelsAvailable() async -> Bool {
        foundationModelsAvailable
    }

    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget
    ) async throws -> SummaryGenerationOutput? {
        summaryCalls += 1
        return summaryOutput
    }

    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput? {
        tagSuggestionCalls += 1
        mostRecentTagSuggestionInput = input
        return tagSuggestionOutput
    }

    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput? {
        scoreAssistCalls += 1
        return scoreAssistOutput
    }

    func scoreAssistCallCount() -> Int {
        scoreAssistCalls
    }

    func tagSuggestionCallCount() -> Int {
        tagSuggestionCalls
    }

    func lastTagSuggestionInput() -> TagSuggestionInput? {
        mostRecentTagSuggestionInput
    }
}
