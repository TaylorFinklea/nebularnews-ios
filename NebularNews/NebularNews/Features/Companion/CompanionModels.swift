import Foundation

struct CompanionSessionPayload: Decodable {
    let session: CompanionSession
    let server: CompanionServer
    let features: CompanionFeatureFlags
}

struct CompanionSession: Decodable {
    let authenticated: Bool
    let clientId: String
    let userId: String
    let scope: String
    let scopes: [String]
}

struct CompanionServer: Decodable {
    let origin: String?
    let resource: String?
}

struct CompanionFeatureFlags: Decodable {
    let dashboard: Bool
    let newsBrief: Bool
    let reactions: Bool
    let tags: Bool
}

struct CompanionDashboardPayload: Decodable {
    let hasFeeds: Bool
    let newsBrief: CompanionNewsBrief?
    let readingQueue: [CompanionArticleListItem]
    let momentum: CompanionReadingMomentum
}

struct CompanionNewsBrief: Decodable {
    struct Bullet: Decodable, Identifiable {
        struct Source: Decodable, Identifiable {
            let articleId: String
            let title: String
            let canonicalUrl: String?

            var id: String { articleId }
        }

        let text: String
        let sources: [Source]

        var id: String { text }
    }

    let state: String
    let title: String
    let editionLabel: String
    let generatedAt: Int?
    let windowHours: Int
    let scoreCutoff: Int
    let bullets: [Bullet]
    let nextScheduledAt: Int?
    let stale: Bool
}

struct CompanionReadingMomentum: Decodable {
    let unreadTotal: Int?
    let unread24h: Int?
    let unread7d: Int?
    let highFitUnread7d: Int?
}

struct CompanionArticlesPayload: Decodable {
    let articles: [CompanionArticleListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct CompanionArticleListItem: Decodable, Identifiable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: String?
    let fetchedAt: String?
    let excerpt: String?
    let summaryText: String?
    let isRead: Int?
    let reactionValue: Int?
    let reactionReasonCodes: [String]?
    let score: Int?
    let scoreLabel: String?
    let scoreStatus: String?
    let scoreConfidence: Double?
    let sourceName: String?
    let sourceFeedId: String?
    let tags: [CompanionTag]?
}

struct CompanionArticleDetailPayload: Decodable {
    let article: CompanionArticle
    let summary: CompanionArticleSummary?
    let keyPoints: CompanionKeyPoints?
    let score: CompanionScore?
    let feedback: [CompanionFeedback]
    var reaction: CompanionReaction?
    let preferredSource: CompanionSource?
    let sources: [CompanionSource]
    var tags: [CompanionTag]
    let tagSuggestions: [CompanionTagSuggestion]
}

struct CompanionArticle: Decodable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: String?
    let fetchedAt: String?
    let contentHtml: String?
    let contentText: String?
    let excerpt: String?
    let wordCount: Int?
    let isRead: Int?
}

struct CompanionArticleSummary: Decodable {
    let summaryText: String?
    let provider: String?
    let model: String?
    let createdAt: Int?
}

struct CompanionKeyPoints: Decodable {
    let keyPointsJson: String?
    let provider: String?
    let model: String?
    let createdAt: Int?
}

struct CompanionScore: Decodable {
    let score: Int?
    let label: String?
    let reasonText: String?
    let evidenceJson: String?
    let createdAt: Int?
    let source: String?
    let status: String?
    let confidence: Double?
    let preferenceConfidence: Double?
    let weightedAverage: Double?
}

struct CompanionFeedback: Decodable, Identifiable {
    let rating: Int?
    let comment: String?
    let createdAt: Int?

    var id: String { "\(createdAt ?? 0)-\(rating ?? 0)-\(comment ?? "")" }
}

struct CompanionReaction: Decodable {
    let articleId: String?
    let feedId: String?
    let value: Int
    let createdAt: Int?
    let reasonCodes: [String]?
}

struct CompanionSource: Decodable, Identifiable {
    let feedId: String?
    let feedTitle: String?
    let siteUrl: String?
    let feedUrl: String?
    let reputation: Double?
    let feedbackCount: Int?

    var id: String { feedId ?? feedUrl ?? UUID().uuidString }
}

struct CompanionTag: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct CompanionTagSuggestion: Decodable, Identifiable {
    let id: String
    let name: String
    let confidence: Double?
}

struct CompanionFeedListPayload: Decodable {
    let feeds: [CompanionFeed]
}

struct CompanionFeed: Decodable, Identifiable {
    let id: String
    let url: String
    let title: String?
    let siteUrl: String?
    let lastPolledAt: Int?
    let nextPollAt: Int?
    let errorCount: Int?
    let disabled: Int?
    let articleCount: Int?
}

struct CompanionReactionResponse: Decodable {
    let reaction: CompanionReaction
}

struct CompanionTagMutationResponse: Decodable {
    let articleId: String?
    let tags: [CompanionTag]
}

// MARK: - Filter types for article list

enum CompanionReadFilter: String, CaseIterable {
    case all = "all"
    case unread = "unread"
    case read = "read"

    var label: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .read: "Read"
        }
    }
}

enum CompanionSortOrder: String, CaseIterable {
    case newest = "newest"
    case oldest = "oldest"
    case score = "score"

    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .score: "Best fit"
        }
    }
}

struct CompanionArticleFilter: Equatable {
    var readFilter: CompanionReadFilter = .all
    var minScore: Int? = nil
    var sortOrder: CompanionSortOrder = .newest

    var isActive: Bool {
        readFilter != .all || minScore != nil || sortOrder != .newest
    }

    mutating func reset() {
        readFilter = .all
        minScore = nil
        sortOrder = .newest
    }
}
