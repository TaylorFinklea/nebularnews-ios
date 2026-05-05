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
            .prefix(20)
            .map { "- \($0.name) [\($0.isCanonical ? "canonical" : "provisional")]" }
            .joined(separator: "\n")

        let prompt = """
        Review this article for possible new taxonomy tags.

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

    public func generateChat(
        messages: [GenerationChatMessage],
        articleContext: ArticleSnapshot?
    ) async throws -> ChatGenerationOutput {
        let (prompt, systemMsg) = Self.buildChatPrompt(messages: messages, articleContext: articleContext)
        let text = try await respond(to: prompt, instructions: systemMsg)
        return ChatGenerationOutput(content: text, provider: provider, modelIdentifier: modelIdentifier)
    }

    /// Streams an on-device chat response token-by-token. The backing
    /// `LanguageModelSession.streamResponse` yields snapshots containing
    /// the cumulative string so far, so we diff against the previous
    /// snapshot to surface only the newly generated suffix as a delta.
    public func streamChat(
        messages: [GenerationChatMessage],
        articleContext: ArticleSnapshot?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard Self.runtimeAvailable else {
                    continuation.finish(throwing: FoundationModelsEngineError.unavailable)
                    return
                }

                let (prompt, systemMsg) = Self.buildChatPrompt(messages: messages, articleContext: articleContext)

                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    do {
                        let session = LanguageModelSession(instructions: systemMsg)
                        let options = GenerationOptions(sampling: .greedy)
                        let stream = session.streamResponse(to: prompt, options: options)
                        var previous = ""
                        for try await snapshot in stream {
                            if Task.isCancelled { break }
                            // For text-only streams, `snapshot.content` is the
                            // cumulative String generated so far. String
                            // interpolation is robust whether content is
                            // `String` or `String.PartiallyGenerated` (which
                            // is `String` in practice for plain text).
                            let current = "\(snapshot.content)"
                            if current.count > previous.count {
                                let delta = String(current.dropFirst(previous.count))
                                continuation.yield(delta)
                                previous = current
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                #endif
                continuation.finish(throwing: FoundationModelsEngineError.unavailable)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func buildChatPrompt(
        messages: [GenerationChatMessage],
        articleContext: ArticleSnapshot?
    ) -> (prompt: String, systemMsg: String) {
        var contextParts: [String] = []

        if let article = articleContext {
            contextParts.append("Article: \(article.title ?? "Untitled")")
            contextParts.append("URL: \(article.canonicalUrl ?? "Unknown")")
            if !article.contentText.isEmpty {
                let truncated = article.contentText.prefix(6000)
                contextParts.append("Content:\n\(truncated)")
            }
        }

        let conversationHistory = messages
            .filter { $0.role != "system" }
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n\n")

        let systemMsg = messages.first(where: { $0.role == "system" })?.content
            ?? "You are an expert news analyst. Be concise and thorough."

        let prompt = """
        \(contextParts.isEmpty ? "" : contextParts.joined(separator: "\n") + "\n\n---\n\n")
        \(conversationHistory)
        """

        return (prompt, systemMsg)
    }

    public func generateBrief(
        articles: [ArticleSnapshot],
        settings: BriefSettings
    ) async throws -> BriefGenerationOutput {
        let articleList = articles.enumerated().map { idx, a in
            "[\(idx + 1)] \(a.title ?? "Untitled") (\(a.feedTitle ?? "Unknown"))\n\(a.contentText.prefix(500))"
        }.joined(separator: "\n\n")

        let prompt = """
        Create a news brief from these articles.

        Articles:
        \(articleList)

        Requirements:
        - Return JSON only.
        - JSON key "bullets": array of objects with:
          - "text": one sentence, max \(settings.maxWordsPerBullet) words
          - "source_index": the article number [1], [2], etc.
        - Maximum \(settings.maxBullets) bullets.
        - Focus on the most important/interesting stories.
        """

        let text = try await respond(
            to: prompt,
            instructions: "You write concise newsroom briefings. Return only compact JSON."
        )

        return try parseBriefOutput(from: text, articles: articles)
    }

    private func parseBriefOutput(from text: String, articles: [ArticleSnapshot]) throws -> BriefGenerationOutput {
        guard let data = text.data(using: .utf8),
              let json = try? extractJSON(from: data) as? [String: Any],
              let bullets = json["bullets"] as? [[String: Any]] else {
            throw FoundationModelsEngineError.invalidResponse
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

    private func extractJSON(from data: Data) throws -> Any {
        // Try direct parse.
        if let json = try? JSONSerialization.jsonObject(with: data) { return json }
        // Strip markdown fences.
        let text = String(data: data, encoding: .utf8) ?? ""
        if let match = text.range(of: "```(?:json)?\\s*\\n?([\\s\\S]*?)```", options: .regularExpression),
           let inner = text[match].range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            let cleaned = Data(text[inner].utf8)
            return try JSONSerialization.jsonObject(with: cleaned)
        }
        // Slice from first { to last }.
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let cleaned = Data(text[start...end].utf8)
            return try JSONSerialization.jsonObject(with: cleaned)
        }
        throw FoundationModelsEngineError.invalidResponse
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
