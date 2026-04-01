import Foundation
import SwiftData

@Model
final class CachedArticle {
    @Attribute(.unique) var id: String
    var canonicalUrl: String?
    var title: String?
    var author: String?
    var publishedAt: Date?
    var fetchedAt: Date?
    var excerpt: String?
    var wordCount: Int?
    var imageUrl: String?
    var contentHtml: String?
    var contentText: String?

    // AI content (cached from Supabase)
    var summaryText: String?
    var keyPointsJson: String?

    // Per-user state
    var isRead: Bool = false
    var savedAt: Date?
    var reactionValue: Int?

    // Score
    var score: Int?
    var scoreLabel: String?
    var scoreStatus: String?
    var scoreConfidence: Double?

    // Source info
    var sourceName: String?
    var sourceFeedId: String?

    // Tags (stored as JSON array of {id, name} objects)
    var tagsJson: String?

    // Cache metadata
    var cachedAt: Date = Date()
    var lastSyncedAt: Date?

    init(id: String) {
        self.id = id
    }
}
