import Foundation
import SwiftData

/// A single article fetched from an RSS feed.
///
/// Articles hold both the raw content (HTML) and AI-generated enrichments
/// (summary, score, key points). User state (read, reactions, tags) is
/// tracked directly on the model for simplicity in v1.
@Model
public final class Article {
    public var id: String = UUID().uuidString
    public var canonicalUrl: String?
    public var title: String?
    public var author: String?
    public var publishedAt: Date?
    public var fetchedAt: Date = Date()

    // Content
    public var contentHtml: String?
    public var excerpt: String?
    public var imageUrl: String?
    public var contentHash: String?

    // AI-generated enrichments
    public var summaryText: String?
    public var summaryProvider: String?
    public var keyPointsJson: String?
    public var score: Int?
    public var scoreLabel: String?
    public var scoreConfidence: Double?
    public var scoreExplanation: String?
    public var aiProcessedAt: Date?

    // User state
    public var isRead: Bool = false
    public var readAt: Date?
    public var reactionValue: Int?
    public var reactionReasonCodes: String?
    public var feedbackRating: Int?

    // Relationships
    public var feed: Feed?

    @Relationship(deleteRule: .nullify, inverse: \Tag.articles)
    public var tags: [Tag]? = []

    public init(canonicalUrl: String? = nil, title: String? = nil) {
        self.id = UUID().uuidString
        self.canonicalUrl = canonicalUrl
        self.title = title
        self.fetchedAt = Date()
    }

    // MARK: - Computed Helpers

    /// Decoded key points from the JSON string.
    public var keyPoints: [String] {
        guard let json = keyPointsJson,
              let data = json.data(using: .utf8),
              let points = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return points
    }

    /// Human-readable score label, falling back to a default.
    public var displayScoreLabel: String {
        scoreLabel ?? score.map { "Score \($0)" } ?? "Unscored"
    }
}
