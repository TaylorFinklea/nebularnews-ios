import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FoundationModelsEngineError: LocalizedError {
    case unavailable
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Foundation Models is not available on this device."
        case .invalidResponse:
            return "Foundation Models returned an invalid response."
        }
    }
}

public struct FoundationModelsEngine: ArticleGenerationEngine {
    public let provider: AIGenerationProvider = .foundationModels
    private let modelIdentifier: String? = "system"

    public init() {}

    public func isAvailable() async -> Bool {
        Self.runtimeAvailable
    }

    public func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String
    ) async throws -> SummaryGenerationOutput {
        let prompt = """
        Summarize the article and extract key points.

        Title: \(snapshot.title ?? "Untitled")
        URL: \(snapshot.canonicalUrl ?? "Unknown")
        Feed: \(snapshot.feedTitle ?? "Unknown")

        Requirements:
        - Return JSON only.
        - JSON keys:
          - "card_summary": exactly one sentence, plain text, concise enough for a feed card.
          - "summary": one plain-text paragraph using the \(summaryStyle) style.
          - "key_points": exactly 4 short strings.
        - The paragraph summary should be 3-5 sentences and feel complete, not just headline-like.
        - Each key point must be <= 14 words.
        - Keep the summary factual and compact.

        Article:
        \(snapshot.contentText)
        """

        let text = try await respond(
            to: prompt,
            instructions: "You are Nebular News. Return only compact JSON that follows the requested schema."
        )

        return try parseSummaryOutput(
            from: text,
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    public func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput {
        let candidateList = input.existingCandidates
            .prefix(24)
            .map { "- \($0.name)" }
            .joined(separator: "\n")

        let prompt = """
        Review this article for possible new taxonomy tags.

        Title: \(input.title ?? "Untitled")
        URL: \(input.canonicalURL ?? "Unknown")
        Feed: \(input.feedTitle ?? "Unknown")
        Current attached tags: \(input.attachedTags.joined(separator: ", "))

        Existing tag candidates:
        \(candidateList.isEmpty ? "- None" : candidateList)

        Rules:
        - Return JSON only.
        - JSON keys:
          - "new_suggestions": array of objects with:
            - "name": short title-case tag, 1-3 words
            - "confidence": number from 0.0 to 1.0
        - Prefer 0 suggestions.
        - Suggest at most \(input.maxSuggestions) new tags.
        - Only suggest a new tag when existing candidates do not fit well enough.
        - Never suggest a source name, person name, or generic label like News, Update, or Article.

        Article:
        \(input.contentText ?? "")
        """

        let text = try await respond(
            to: prompt,
            instructions: "You classify articles into reusable taxonomy tags and strongly prefer existing tags."
        )

        return TagSuggestionOutput(
            suggestions: try parseTagSuggestionCandidates(from: text, maxSuggestions: input.maxSuggestions),
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    public func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput {
        let prompt = """
        Review this existing article-fit score.

        Title: \(input.title ?? "Untitled")
        URL: \(input.canonicalURL ?? "Unknown")
        Algorithmic score: \(input.algorithmicScore)/5
        Mode: \(input.scoreAssistMode.rawValue)

        Algorithmic explanation:
        \(input.algorithmicExplanation)

        Signal summary:
        \(input.signalSummary)

        Requirements:
        - Return JSON only.
        - JSON keys:
          - "explanation": one short paragraph
          - "adjustment": integer in {-1, 0, 1}
        - If mode is explain_only, "adjustment" must be 0.
        - Be conservative and prefer 0 adjustment.

        Article:
        \(input.contentText ?? "")
        """

        let text = try await respond(
            to: prompt,
            instructions: "You explain or cautiously adjust an existing relevance score. Return only compact JSON."
        )

        return try parseScoreAssistOutput(
            from: text,
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    public static var runtimeAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    private func respond(to prompt: String, instructions: String) async throws -> String {
        guard Self.runtimeAvailable else {
            throw FoundationModelsEngineError.unavailable
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(sampling: .greedy)
            let response = try await session.respond(to: prompt, options: options)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw FoundationModelsEngineError.invalidResponse
            }
            return content
        }
        #endif

        throw FoundationModelsEngineError.unavailable
    }
}
