import Foundation
import SwiftData

// MARK: - Enrichment Result

/// Result of AI enrichment for a single article.
public struct EnrichmentResult: Sendable {
    public let articleId: String
    public let score: Int?
    public let scoreLabel: String?
    public let scoreExplanation: String?
    public let summary: String?
    public let keyPoints: [String]?
    public let error: String?

    public var succeeded: Bool { error == nil }
}

// MARK: - Service

/// Orchestrates AI enrichment (scoring, summarization, key point extraction) for articles.
///
/// Runs as an `actor` — its own isolation domain separate from MainActor — because
/// it coordinates multi-step LLM calls that shouldn't block the UI. Each article
/// goes through up to three sequential API calls (score → summary → key points),
/// run sequentially to respect Anthropic rate limits.
public actor AIEnrichmentService {
    private let client: AnthropicClient
    private let articleRepo: LocalArticleRepository

    /// Maximum characters of article content to send in prompts.
    /// ~12k chars ≈ ~3k tokens, well within Haiku's context window.
    private let maxContentLength = 12_000

    public init(client: AnthropicClient, articleRepo: LocalArticleRepository) {
        self.client = client
        self.articleRepo = articleRepo
    }

    // MARK: - Public API

    /// Enrich a single article with AI-generated score, summary, and key points.
    public func enrichArticle(
        snapshot: ArticleSnapshot,
        userProfile: String?,
        scoringModel: String,
        summaryModel: String,
        summaryStyle: String
    ) async -> EnrichmentResult {
        let content = snapshot.contentText.truncated(to: maxContentLength)
        let title = snapshot.title ?? "Untitled"
        let url = snapshot.canonicalUrl ?? ""

        var score: Int?
        var scoreLabel: String?
        var scoreExplanation: String?
        var summary: String?
        var keyPoints: [String]?

        // Step 1: Score (only if user has a profile configured)
        if let profile = userProfile, !profile.isEmpty {
            do {
                let result = try await scoreArticle(
                    title: title, url: url, content: content,
                    profile: profile, model: scoringModel
                )
                score = result.score
                scoreLabel = result.label
                scoreExplanation = result.reason
            } catch {
                // Non-fatal — continue with summary/key points
                print("[AIEnrichment] Scoring failed for \(snapshot.id): \(error.localizedDescription)")
            }
        }

        // Step 2: Summary
        do {
            summary = try await summarizeArticle(
                title: title, url: url, content: content,
                style: summaryStyle, model: summaryModel
            )
        } catch {
            print("[AIEnrichment] Summary failed for \(snapshot.id): \(error.localizedDescription)")
        }

        // Step 3: Key points
        do {
            keyPoints = try await extractKeyPoints(
                title: title, url: url, content: content,
                model: summaryModel
            )
        } catch {
            print("[AIEnrichment] Key points failed for \(snapshot.id): \(error.localizedDescription)")
        }

        // Persist results
        do {
            try await articleRepo.updateAIFields(
                id: snapshot.id,
                summary: summary,
                keyPoints: keyPoints,
                score: score,
                scoreLabel: scoreLabel,
                scoreExplanation: scoreExplanation
            )
        } catch {
            return EnrichmentResult(
                articleId: snapshot.id, score: score, scoreLabel: scoreLabel,
                scoreExplanation: scoreExplanation, summary: summary,
                keyPoints: keyPoints, error: "Failed to save: \(error.localizedDescription)"
            )
        }

        return EnrichmentResult(
            articleId: snapshot.id, score: score, scoreLabel: scoreLabel,
            scoreExplanation: scoreExplanation, summary: summary,
            keyPoints: keyPoints, error: nil
        )
    }

    /// Enrich multiple unprocessed articles. Runs sequentially to respect rate limits.
    public func enrichUnprocessedArticles(
        limit: Int = 5,
        userProfile: String?,
        scoringModel: String,
        summaryModel: String,
        summaryStyle: String
    ) async -> [EnrichmentResult] {
        let snapshots = await articleRepo.listUnprocessedSnapshots(limit: limit)
        var results: [EnrichmentResult] = []

        for snapshot in snapshots {
            // Check cancellation between articles
            if Task.isCancelled { break }

            let result = await enrichArticle(
                snapshot: snapshot,
                userProfile: userProfile,
                scoringModel: scoringModel,
                summaryModel: summaryModel,
                summaryStyle: summaryStyle
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Scoring

    private func scoreArticle(
        title: String, url: String, content: String,
        profile: String, model: String
    ) async throws -> ScoreResult {
        let systemPrompt = "You are a transparent relevance scorer. Judge fit against the user profile only, not writing quality."

        let userPrompt = """
        You are scoring how well this article matches the user's preferences.

        Preferences:
        \(profile)

        Article:
        Title: \(title)
        URL: \(url)

        Content:
        \(content)

        Return JSON only with keys:
        - score (1-5 integer)
        - label (short text)
        - reason (one paragraph)
        - evidence (array of short quoted snippets from article content)
        """

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: userPrompt)],
            system: systemPrompt,
            model: model,
            maxTokens: 800,
            temperature: 0.2
        )

        return try parseScoreResponse(response.text)
    }

    private struct ScoreResult {
        let score: Int
        let label: String
        let reason: String
    }

    private func parseScoreResponse(_ text: String) throws -> ScoreResult {
        guard let data = extractJSON(from: text)?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = json["score"] as? Int else {
            throw AnthropicError.parseError(detail: "Could not parse score JSON")
        }

        let label = json["label"] as? String ?? scoreLabelForScore(score)
        let reason = json["reason"] as? String ?? ""

        return ScoreResult(
            score: max(1, min(5, score)),
            label: label,
            reason: reason
        )
    }

    // MARK: - Summarization

    private func summarizeArticle(
        title: String, url: String, content: String,
        style: String, model: String
    ) async throws -> String {
        let systemPrompt = "You are Nebular News. Follow formatting constraints exactly."

        let instructions = summaryInstructions(for: style)

        let userPrompt = """
        Summarize the article below.

        Title: \(title)
        URL: \(url)

        Instructions:
        \(instructions)

        Content:
        \(content)
        """

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: userPrompt)],
            system: systemPrompt,
            model: model,
            maxTokens: 400,
            temperature: 0.2
        )

        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryInstructions(for style: String) -> String {
        switch style {
        case "bullets":
            return """
            Write 4 concise bullet points only.
            - Each bullet must be <= 14 words.
            - No intro text and no conclusion.
            - Output plain text bullets.
            """
        case "detailed":
            return """
            Write a plain-text summary paragraph (no bullets, no numbering, no markdown).
            - Target 95-170 words.
            - Cover the main argument, key evidence, and outcome.
            - Do not include a "Key points" section.
            """
        default: // "concise"
            return """
            Write a single plain-text paragraph (no bullets, no numbering, no markdown).
            - Target 28-55 words.
            - Keep only the most important facts and outcome.
            - Do not include a "Key points" section.
            """
        }
    }

    // MARK: - Key Points

    private func extractKeyPoints(
        title: String, url: String, content: String,
        model: String
    ) async throws -> [String] {
        let systemPrompt = "You extract high-signal key points for quick scanning."

        let userPrompt = """
        Extract the key points from this article.

        Title: \(title)
        URL: \(url)

        Requirements:
        - Return JSON only with key "key_points" (array of strings).
        - Provide exactly 4 points.
        - Each point must be <= 14 words.
        - Focus on facts, outcomes, and concrete signals.

        Article:
        \(content)
        """

        let response = try await client.chat(
            messages: [AIMessage(role: "user", content: userPrompt)],
            system: systemPrompt,
            model: model,
            maxTokens: 400,
            temperature: 0.2
        )

        return try parseKeyPointsResponse(response.text)
    }

    private func parseKeyPointsResponse(_ text: String) throws -> [String] {
        guard let jsonString = extractJSON(from: text),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let points = json["key_points"] as? [String] else {
            throw AnthropicError.parseError(detail: "Could not parse key_points JSON")
        }
        return points
    }

    // MARK: - Helpers

    /// Extract JSON from LLM response text, handling markdown code fences.
    private func extractJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try extracting from ```json ... ``` code fence
        if let range = trimmed.range(of: "```json") ?? trimmed.range(of: "```") {
            let afterFence = trimmed[range.upperBound...]
            if let endRange = afterFence.range(of: "```") {
                return String(afterFence[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try parsing as raw JSON (starts with {)
        if trimmed.hasPrefix("{") {
            return trimmed
        }

        return nil
    }

    /// Default score label for a given 1-5 score.
    ///
    /// TODO: User contribution — this maps scores to human-readable labels.
    /// The labels shape how users perceive relevance. Consider what language
    /// best communicates the scoring signal for your reading workflow.
    private func scoreLabelForScore(_ score: Int) -> String {
        switch score {
        case 5: return "Perfect match"
        case 4: return "Strong fit"
        case 3: return "Moderate fit"
        case 2: return "Weak fit"
        case 1: return "Low relevance"
        default: return "Unscored"
        }
    }
}
