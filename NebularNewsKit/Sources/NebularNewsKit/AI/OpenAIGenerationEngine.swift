import Foundation

public enum OpenAIEngineError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .serverError(let statusCode, let body):
            return "OpenAI error (\(statusCode)): \(body)"
        }
    }
}

public struct OpenAIGenerationEngine: ArticleGenerationEngine {
    public let provider: AIGenerationProvider = .openAI

    private let apiKey: String
    private let modelIdentifier: String
    private let session: URLSession

    public init(apiKey: String, modelIdentifier: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelIdentifier = modelIdentifier
        self.session = session
    }

    public func isAvailable() async -> Bool { true }

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
          - "card_summary": exactly one plain-text sentence for a feed card.
          - "summary": one plain-text paragraph, concise but complete.
          - "key_points": exactly 4 short strings.
        - The card summary must stand alone and stay under 24 words.
        - The paragraph summary should be 3-5 sentences.
        - Keep the summary style \(summaryStyle).
        - Each key point must be <= 14 words.

        Article:
        \(snapshot.contentText)
        """

        let text = try await complete(
            system: "You are Nebular News. Return only compact JSON that follows the requested schema.",
            user: prompt
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
            .prefix(20)
            .map { "- \($0.name) [\($0.isCanonical ? "canonical" : "provisional")]" }
            .joined(separator: "\n")

        let prompt = """
        Suggest at most \(input.maxSuggestions) strongly recommended new taxonomy tags for this article.

        Title: \(input.title ?? "Untitled")
        URL: \(input.canonicalURL ?? "Unknown")
        Author: \(input.author ?? "Unknown")
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
        - Only suggest a new tag if none of the existing candidates fit well enough.
        - Never suggest a source name, person name, or generic label like News, Update, or Article.
        - Maximum \(input.maxSuggestions) suggestions.

        Article:
        \(input.contentText ?? "")
        """

        let text = try await complete(
            system: "You classify articles into reusable taxonomy tags and prefer existing tags over creating new ones.",
            user: prompt
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
        Review this algorithmic article score.

        Title: \(input.title ?? "Untitled")
        URL: \(input.canonicalURL ?? "Unknown")
        Algorithmic score: \(input.algorithmicScore)/5
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
        - Be conservative. Only adjust when there is a strong reason.

        Mode: \(input.scoreAssistMode.rawValue)

        Article:
        \(input.contentText ?? "")
        """

        let text = try await complete(
            system: "You help explain or cautiously adjust an existing article-fit score. Return only compact JSON.",
            user: prompt
        )

        return try parseScoreAssistOutput(
            from: text,
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    private func complete(system: String, user: String) async throws -> String {
        let payload: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIEngineError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAIEngineError.serverError(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? "Unknown error"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw OpenAIEngineError.invalidResponse
        }

        return content
    }
}
