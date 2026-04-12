import Foundation

public enum AIGenerationProvider: String, Codable, Sendable {
    case foundationModels = "foundation_models"
    case anthropic = "anthropic"
    case openAI = "openai"
}

public enum AIExplicitGenerationTarget: Sendable {
    case automatic
    case anthropic
    case openAI
}

public struct SummaryGenerationOutput: Sendable {
    public let cardSummary: String
    public let summary: String
    public let keyPoints: [String]
    public let provider: AIGenerationProvider
    public let modelIdentifier: String?

    public init(
        cardSummary: String,
        summary: String,
        keyPoints: [String],
        provider: AIGenerationProvider,
        modelIdentifier: String?
    ) {
        self.cardSummary = cardSummary
        self.summary = summary
        self.keyPoints = keyPoints
        self.provider = provider
        self.modelIdentifier = modelIdentifier
    }
}

public struct SuggestedTagCandidate: Sendable, Hashable {
    public let name: String
    public let confidence: Double

    public init(name: String, confidence: Double) {
        self.name = name
        self.confidence = confidence
    }
}

public struct TagSuggestionOutput: Sendable {
    public let suggestions: [SuggestedTagCandidate]
    public let provider: AIGenerationProvider
    public let modelIdentifier: String?

    public init(
        suggestions: [SuggestedTagCandidate],
        provider: AIGenerationProvider,
        modelIdentifier: String?
    ) {
        self.suggestions = suggestions
        self.provider = provider
        self.modelIdentifier = modelIdentifier
    }
}

public struct ExistingTagSuggestionCandidate: Sendable, Hashable {
    public let id: String
    public let name: String
    public let matchScore: Double
    public let articleCount: Int
    public let isCanonical: Bool
    public let phraseHit: Bool
    public let tokenOverlapCount: Int

    public init(
        id: String,
        name: String,
        matchScore: Double,
        articleCount: Int,
        isCanonical: Bool = false,
        phraseHit: Bool = false,
        tokenOverlapCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.matchScore = matchScore
        self.articleCount = articleCount
        self.isCanonical = isCanonical
        self.phraseHit = phraseHit
        self.tokenOverlapCount = tokenOverlapCount
    }
}

public struct TagSuggestionInput: Sendable {
    public let articleID: String
    public let title: String?
    public let canonicalURL: String?
    public let contentText: String?
    public let author: String?
    public let feedTitle: String?
    public let siteHostname: String?
    public let attachedTags: [String]
    public let existingCandidates: [ExistingTagSuggestionCandidate]
    public let maxSuggestions: Int

    public init(
        articleID: String,
        title: String?,
        canonicalURL: String?,
        contentText: String?,
        author: String? = nil,
        feedTitle: String?,
        siteHostname: String?,
        attachedTags: [String],
        existingCandidates: [ExistingTagSuggestionCandidate],
        maxSuggestions: Int
    ) {
        self.articleID = articleID
        self.title = title
        self.canonicalURL = canonicalURL
        self.contentText = contentText
        self.author = author
        self.feedTitle = feedTitle
        self.siteHostname = siteHostname
        self.attachedTags = attachedTags
        self.existingCandidates = existingCandidates
        self.maxSuggestions = maxSuggestions
    }
}

public struct ScoreAssistInput: Sendable {
    public let title: String?
    public let canonicalURL: String?
    public let contentText: String?
    public let algorithmicScore: Int
    public let algorithmicExplanation: String
    public let signalSummary: String
    public let scoreAssistMode: AIScoreAssistMode

    public init(
        title: String?,
        canonicalURL: String?,
        contentText: String?,
        algorithmicScore: Int,
        algorithmicExplanation: String,
        signalSummary: String,
        scoreAssistMode: AIScoreAssistMode
    ) {
        self.title = title
        self.canonicalURL = canonicalURL
        self.contentText = contentText
        self.algorithmicScore = algorithmicScore
        self.algorithmicExplanation = algorithmicExplanation
        self.signalSummary = signalSummary
        self.scoreAssistMode = scoreAssistMode
    }
}

public struct ScoreAssistOutput: Sendable {
    public let explanation: String
    public let adjustment: Int
    public let provider: AIGenerationProvider
    public let modelIdentifier: String?

    public init(
        explanation: String,
        adjustment: Int,
        provider: AIGenerationProvider,
        modelIdentifier: String?
    ) {
        self.explanation = explanation
        self.adjustment = adjustment
        self.provider = provider
        self.modelIdentifier = modelIdentifier
    }
}

// MARK: - Chat Types

public struct GenerationChatMessage: Sendable {
    public let role: String // "system", "user", "assistant"
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatGenerationOutput: Sendable {
    public let content: String
    public let provider: AIGenerationProvider
    public let modelIdentifier: String?

    public init(content: String, provider: AIGenerationProvider, modelIdentifier: String?) {
        self.content = content
        self.provider = provider
        self.modelIdentifier = modelIdentifier
    }
}

// MARK: - Brief Types

public struct BriefSettings: Sendable {
    public let maxBullets: Int
    public let maxWordsPerBullet: Int

    public init(maxBullets: Int = 5, maxWordsPerBullet: Int = 18) {
        self.maxBullets = maxBullets
        self.maxWordsPerBullet = maxWordsPerBullet
    }
}

public struct BriefBullet: Sendable {
    public let text: String
    public let sourceArticleId: String?

    public init(text: String, sourceArticleId: String?) {
        self.text = text
        self.sourceArticleId = sourceArticleId
    }
}

public struct BriefGenerationOutput: Sendable {
    public let bullets: [BriefBullet]
    public let provider: AIGenerationProvider
    public let modelIdentifier: String?

    public init(bullets: [BriefBullet], provider: AIGenerationProvider, modelIdentifier: String?) {
        self.bullets = bullets
        self.provider = provider
        self.modelIdentifier = modelIdentifier
    }
}

// MARK: - Engine Protocol

public protocol ArticleGenerationEngine: Sendable {
    var provider: AIGenerationProvider { get }
    func isAvailable() async -> Bool
    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String
    ) async throws -> SummaryGenerationOutput
    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput
    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput
    func generateChat(
        messages: [GenerationChatMessage],
        articleContext: ArticleSnapshot?
    ) async throws -> ChatGenerationOutput
    func generateBrief(
        articles: [ArticleSnapshot],
        settings: BriefSettings
    ) async throws -> BriefGenerationOutput
}
