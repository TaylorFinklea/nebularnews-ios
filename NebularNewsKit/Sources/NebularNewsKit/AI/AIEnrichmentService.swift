import Foundation
import SwiftData

// MARK: - Enrichment Result

public enum AIEnrichmentAttemptStatus: Sendable {
    case generated
    case skipped
    case failed
}

/// Result of AI enrichment for a single article.
public struct EnrichmentResult: Sendable {
    public let articleId: String
    public let summary: String?
    public let keyPoints: [String]?
    public let status: AIEnrichmentAttemptStatus
    public let error: String?

    public var succeeded: Bool { status == .generated && error == nil }
}

// MARK: - Service

/// Orchestrates optional AI enrichment (summarization and key point extraction) for articles.
///
/// Runs as an `actor` — its own isolation domain separate from MainActor — because
/// it coordinates multi-step LLM calls that shouldn't block the UI. Each article
/// goes through one local-first generation pass and only uses external models
/// when explicitly requested or when fallback is enabled.
public actor AIEnrichmentService {
    private let coordinator: any AIGenerationCoordinating
    private let articleRepo: LocalArticleRepository

    /// Maximum characters of article content to send in prompts.
    /// ~12k chars ≈ ~3k tokens, well within Haiku's context window.
    private let maxContentLength = 12_000

    public init(coordinator: any AIGenerationCoordinating, articleRepo: LocalArticleRepository) {
        self.coordinator = coordinator
        self.articleRepo = articleRepo
    }

    public init(
        modelContainer: ModelContainer,
        keychainService: String = "com.nebularnews.ios",
        generationCoordinator: (any AIGenerationCoordinating)? = nil
    ) {
        self.articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        self.coordinator = generationCoordinator
            ?? AIGenerationCoordinator(modelContainer: modelContainer, keychainService: keychainService)
    }

    // MARK: - Public API

    /// Enrich a single article with AI-generated summary and key points.
    public func enrichArticle(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget = .automatic
    ) async -> EnrichmentResult {
        let localSnapshot = ArticleSnapshot(
            id: snapshot.id,
            title: snapshot.title,
            contentText: snapshot.contentText.truncated(to: maxContentLength),
            canonicalUrl: snapshot.canonicalUrl,
            feedTitle: snapshot.feedTitle
        )

        let generated: SummaryGenerationOutput
        do {
            guard let output = try await coordinator.generateSummary(
                snapshot: localSnapshot,
                summaryStyle: summaryStyle,
                target: target
            ) else {
                return EnrichmentResult(
                    articleId: snapshot.id,
                    summary: nil,
                    keyPoints: nil,
                    status: .skipped,
                    error: "No generation provider available"
                )
            }
            generated = output
        } catch {
            return EnrichmentResult(
                articleId: snapshot.id,
                summary: nil,
                keyPoints: nil,
                status: .failed,
                error: error.localizedDescription
            )
        }

        do {
            try await articleRepo.updateAIFields(
                id: snapshot.id,
                cardSummary: generated.cardSummary,
                summary: generated.summary,
                keyPoints: generated.keyPoints,
                score: nil,
                scoreLabel: nil,
                scoreExplanation: nil,
                summaryProvider: generated.provider.rawValue,
                summaryModel: generated.modelIdentifier
            )
        } catch {
            return EnrichmentResult(
                articleId: snapshot.id,
                summary: generated.summary,
                keyPoints: generated.keyPoints,
                status: .failed,
                error: "Failed to save: \(error.localizedDescription)"
            )
        }

        return EnrichmentResult(
            articleId: snapshot.id,
            summary: generated.summary,
            keyPoints: generated.keyPoints,
            status: .generated,
            error: nil
        )
    }

    /// Enrich multiple unprocessed articles. Runs sequentially to respect rate limits.
    public func enrichUnprocessedArticles(
        limit: Int = 5,
        summaryStyle: String
    ) async -> [EnrichmentResult] {
        let snapshots = await articleRepo.listUnprocessedSnapshots(limit: limit)
        var results: [EnrichmentResult] = []

        for snapshot in snapshots {
            // Check cancellation between articles
            if Task.isCancelled { break }

            let result = await enrichArticle(
                snapshot: snapshot,
                summaryStyle: summaryStyle
            )
            results.append(result)
        }

        return results
    }
}
