import Foundation

struct CompanionSessionPayload: Codable {
    let session: CompanionSession
    let server: CompanionServer
    let features: CompanionFeatureFlags
}

struct CompanionSession: Codable {
    let authenticated: Bool
    let clientId: String
    let userId: String
    let scope: String
    let scopes: [String]
}

struct CompanionServer: Codable {
    let origin: String?
    let resource: String?
}

struct CompanionFeatureFlags: Codable {
    let dashboard: Bool
    let newsBrief: Bool
    let reactions: Bool
    let tags: Bool
}

struct CompanionDashboardPayload: Codable {
    let hasFeeds: Bool
    let newsBrief: CompanionNewsBrief?
    let readingQueue: [CompanionArticleListItem]
    let momentum: CompanionReadingMomentum
}

struct CompanionNewsBrief: Codable {
    struct Bullet: Codable, Identifiable {
        struct Source: Codable, Identifiable {
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

struct CompanionReadingMomentum: Codable {
    let unreadTotal: Int?
    let unread24h: Int?
    let unread7d: Int?
    let highFitUnread7d: Int?
}

struct CompanionArticlesPayload: Codable {
    let articles: [CompanionArticleListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct CompanionArticleListItem: Codable, Identifiable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: Int?
    let fetchedAt: Int?
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

struct CompanionArticleDetailPayload: Codable {
    var article: CompanionArticle
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

struct CompanionArticle: Codable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: Int?
    let fetchedAt: Int?
    let contentHtml: String?
    let contentText: String?
    let excerpt: String?
    let wordCount: Int?
    var isRead: Int?
}

struct CompanionArticleSummary: Codable {
    let summaryText: String?
    let provider: String?
    let model: String?
    let createdAt: Int?
}

struct CompanionKeyPoints: Codable {
    let keyPointsJson: String?
    let provider: String?
    let model: String?
    let createdAt: Int?
}

struct CompanionScore: Codable {
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

struct CompanionFeedback: Codable, Identifiable {
    let rating: Int?
    let comment: String?
    let createdAt: Int?

    var id: String { "\(createdAt ?? 0)-\(rating ?? 0)-\(comment ?? "")" }
}

struct CompanionReaction: Codable {
    let articleId: String?
    let feedId: String?
    let value: Int
    let createdAt: Int?
    let reasonCodes: [String]?
}

struct CompanionSource: Codable, Identifiable {
    let feedId: String?
    let feedTitle: String?
    let siteUrl: String?
    let feedUrl: String?
    let reputation: Double?
    let feedbackCount: Int?

    var id: String { feedId ?? feedUrl ?? UUID().uuidString }
}

struct CompanionTag: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct CompanionTagSuggestion: Codable, Identifiable {
    let id: String
    let name: String
    let confidence: Double?
}

struct CompanionFeedListPayload: Codable {
    let feeds: [CompanionFeed]
}

struct CompanionFeed: Codable, Identifiable {
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

struct CompanionReactionResponse: Codable {
    let reaction: CompanionReaction
}

struct CompanionTagMutationResponse: Codable {
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
    case score = "score_desc"
    case unreadFirst = "unread_first"

    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .score: "Best fit"
        case .unreadFirst: "Unread first"
        }
    }
}

struct CompanionArticleFilter: Equatable {
    var readFilter: CompanionReadFilter = .unread
    var minScore: Int? = nil
    var sortOrder: CompanionSortOrder = .newest

    var isActive: Bool {
        readFilter != .unread || minScore != nil || sortOrder != .newest
    }

    mutating func reset() {
        readFilter = .unread
        minScore = nil
        sortOrder = .newest
    }
}

// MARK: - Feed management responses

struct CompanionAddFeedResponse: Codable {
    let ok: Bool
    let id: String
}

struct CompanionDeleteFeedResponse: Codable {
    let ok: Bool
    let deleted: CompanionDeleteStats?
}

struct CompanionDeleteStats: Codable {
    let feeds: Int
    let articles: Int
}

struct CompanionImportOPMLResponse: Codable {
    let ok: Bool
    let added: Int
}

struct CompanionTriggerPullResponse: Codable {
    let ok: Bool?
    let started: Bool?
    let runId: String?
}

// MARK: - Today payload

struct CompanionTodayPayload: Codable {
    let hero: CompanionArticleListItem?
    let upNext: [CompanionArticleListItem]
    let stats: CompanionTodayStats
    let newsBrief: CompanionNewsBrief?
}

struct CompanionTodayStats: Codable {
    let unreadTotal: Int
    let newToday: Int
    let highFitUnread: Int
}

// MARK: - Save response

struct CompanionSaveResponse: Codable {
    let articleId: String
    let saved: Bool
    let savedAt: Int?
}

struct CompanionDismissResponse: Codable {
    let articleId: String
    let dismissed: Bool
}

// MARK: - Settings payload

struct CompanionSettingsPayload: Codable {
    var pollIntervalMinutes: Int
    var summaryStyle: String
    var scoringMethod: String
    var newsBriefConfig: CompanionNewsBriefConfig
    var upNextLimit: Int
    var retentionArchiveDays: Int?
    var retentionDeleteDays: Int?
}

struct CompanionNewsBriefConfig: Codable {
    var enabled: Bool
    var timezone: String
    var morningTime: String
    var eveningTime: String
    var lookbackHours: Int
    var scoreCutoff: Int
}

// MARK: - Tag list payload

struct CompanionTagListPayload: Codable {
    let tags: [CompanionTagWithCount]
}

struct CompanionTagWithCount: Codable, Identifiable {
    let id: String
    let name: String
    let slug: String?
    let color: String?
    let description: String?
    let articleCount: Int
}

struct CompanionCreateTagResponse: Codable {
    let ok: Bool
    let tag: CompanionTagWithCount
}

struct CompanionDeleteTagResponse: Codable {
    let ok: Bool
}

// MARK: - Chat

struct CompanionChatThread: Codable {
    let id: String
    let articleId: String?
    let title: String?
    let createdAt: Int
    let updatedAt: Int
}

struct CompanionChatMessage: Codable, Identifiable {
    let id: String
    let threadId: String
    let role: String
    let content: String
    let tokenCount: Int?
    let provider: String?
    let model: String?
    let createdAt: Int
}

struct CompanionChatPayload: Codable {
    let thread: CompanionChatThread?
    let messages: [CompanionChatMessage]
}

// MARK: - Onboarding catalog

struct OnboardingCatalog: Codable {
    let categories: [OnboardingCategory]
}

struct OnboardingCategory: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let feeds: [OnboardingFeed]
}

struct OnboardingFeed: Codable, Identifiable {
    let url: String
    let title: String
    let description: String?
    let siteUrl: String?

    var id: String { url }
}

struct OnboardingSubscribeResponse: Codable {
    let ok: Bool
    let subscribed: Int
    let runId: String?
}
