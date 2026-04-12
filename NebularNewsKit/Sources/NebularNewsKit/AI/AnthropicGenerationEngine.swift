import Foundation

public struct AnthropicGenerationEngine: ArticleGenerationEngine {
    public let provider: AIGenerationProvider = .anthropic

    private let client: AnthropicClient
    private let modelIdentifier: String

    public init(apiKey: String, modelIdentifier: String) {
        self.client = AnthropicClient(apiKey: apiKey)
        self.modelIdentifier = modelIdentifier
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

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: prompt)],
            system: "You are Nebular News. Return only compact JSON that follows the requested schema.",
            model: modelIdentifier,
            maxTokens: 700,
            temperature: 0.2
        )

        return try parseSummaryOutput(
            from: response.text,
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

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: prompt)],
            system: "You classify articles into reusable taxonomy tags and prefer existing tags over creating new ones.",
            model: modelIdentifier,
            maxTokens: 500,
            temperature: 0.1
        )

        return TagSuggestionOutput(
            suggestions: try parseTagSuggestionCandidates(from: response.text, maxSuggestions: input.maxSuggestions),
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

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: prompt)],
            system: "You help explain or cautiously adjust an existing article-fit score. Return only compact JSON.",
            model: modelIdentifier,
            maxTokens: 500,
            temperature: 0.1
        )

        return try parseScoreAssistOutput(
            from: response.text,
            provider: provider,
            modelIdentifier: modelIdentifier
        )
    }

    public func generateChat(
        messages: [GenerationChatMessage],
        articleContext: ArticleSnapshot?
    ) async throws -> ChatGenerationOutput {
        let systemMsg = messages.first(where: { $0.role == "system" })?.content
            ?? "You are an expert news analyst. Be concise and thorough."

        var aiMessages: [AIMessage] = []

        // Add article context as the first user message if provided.
        if let article = articleContext {
            let contentPreview = String(article.contentText.prefix(6000))
            aiMessages.append(AIMessage(
                role: "user",
                content: "Article: \(article.title ?? "Untitled")\nURL: \(article.canonicalUrl ?? "")\n\nContent:\n\(contentPreview)"
            ))
        }

        // Add conversation history (skip system messages).
        for msg in messages where msg.role != "system" {
            aiMessages.append(AIMessage(role: msg.role, content: msg.content))
        }

        let response = try await client.chat(
            messages: aiMessages,
            system: systemMsg,
            model: modelIdentifier,
            maxTokens: 1024,
            temperature: 0.3
        )

        return ChatGenerationOutput(content: response.text, provider: provider, modelIdentifier: modelIdentifier)
    }

    public func generateBrief(
        articles: [ArticleSnapshot],
        settings: BriefSettings
    ) async throws -> BriefGenerationOutput {
        let articleList = articles.enumerated().map { idx, a in
            "[\(idx + 1)] \(a.title ?? "Untitled") (\(a.feedTitle ?? "Unknown"))\n\(String(a.contentText.prefix(500)))"
        }.joined(separator: "\n\n")

        let prompt = """
        Create a news brief from these articles. Return JSON only.
        JSON key "bullets": array of objects with "text" (max \(settings.maxWordsPerBullet) words) and "source_index" (article number).
        Maximum \(settings.maxBullets) bullets. Focus on the most important stories.

        Articles:
        \(articleList)
        """

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: prompt)],
            system: "You write concise newsroom briefings. Return only compact JSON.",
            model: modelIdentifier,
            maxTokens: 500,
            temperature: 0.2
        )

        // Parse the JSON bullets.
        guard let data = response.text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bullets = json["bullets"] as? [[String: Any]] else {
            return BriefGenerationOutput(bullets: [], provider: provider, modelIdentifier: modelIdentifier)
        }

        let parsed = bullets.compactMap { b -> BriefBullet? in
            guard let text = b["text"] as? String else { return nil }
            let idx = (b["source_index"] as? Int).flatMap { i in
                (i >= 1 && i <= articles.count) ? articles[i - 1].id : nil
            }
            return BriefBullet(text: text, sourceArticleId: idx)
        }

        return BriefGenerationOutput(bullets: parsed, provider: provider, modelIdentifier: modelIdentifier)
    }
}
