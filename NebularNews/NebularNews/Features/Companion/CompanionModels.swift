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
            /// Article title — optional because legacy cron-persisted
            /// briefs synthesized sources from `source_article_ids` and
            /// have no title to attach. New enriched briefs always
            /// populate it.
            let title: String?
            let canonicalUrl: String?

            var id: String { articleId }

            init(articleId: String, title: String?, canonicalUrl: String?) {
                self.articleId = articleId
                self.title = title
                self.canonicalUrl = canonicalUrl
            }
        }

        let text: String
        let sources: [Source]

        var id: String { text }

        /// Two server-side bullet shapes have shipped over time:
        ///   - Enriched (current): `{ text, sources: [{article_id, title, ...}] }`
        ///   - Legacy cron raw:    `{ text, source_article_ids: [String] }`
        /// Both end up in `news_brief_editions.bullets_json` because the
        /// scheduled-briefs cron originally persisted the AI's raw
        /// output verbatim. This decoder accepts either, so brief
        /// history doesn't blow up on pre-enrichment rows. Mirrors the
        /// same dual-shape handling in SeededBrief.Bullet.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.text = try c.decode(String.self, forKey: .text)
            if let enriched = try? c.decode([Source].self, forKey: .sources) {
                self.sources = enriched
            } else if let ids = try? c.decode([String].self, forKey: .sourceArticleIds) {
                self.sources = ids.map { Source(articleId: $0, title: nil, canonicalUrl: nil) }
            } else {
                self.sources = []
            }
        }

        /// Always re-emit the enriched shape — encoder is only used for
        /// markdown export / share paths, never to round-trip back to
        /// the server, so canonicalizing here is fine.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(sources, forKey: .sources)
        }

        /// CodingKey rawValues are camelCase even though the JSON is
        /// snake_case — APIClient's decoder uses `convertFromSnakeCase`
        /// which converts JSON keys to camelCase before lookup. Snake-
        /// case rawValues here would silently mis-match the converted
        /// key (the same bug we fixed on SeededBrief.Bullet.Source).
        enum CodingKeys: String, CodingKey {
            case text
            case sources
            case sourceArticleIds
        }
    }

    let id: String?
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
    /// Last time the user opened this article and accumulated foreground
    /// time. Server only stamps this when time_spent_ms is positive, so
    /// non-nil means "the user genuinely engaged with this", distinct
    /// from `isRead` which can be set by a brief seeing the title.
    /// Powers the Read history surface.
    let lastReadAt: Int?
    let timeSpentMsTotal: Int?

    var isReadBool: Bool { isRead == 1 }
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
    var highlights: [CompanionHighlight]?
    var annotation: CompanionAnnotation?
    // Last-known scroll percent for the current user, populated by the
    // server from article_read_state. Used by CompanionArticleDetailView to
    // auto-restore scroll on reopen (M16 Tier 2). Nil = nothing to restore.
    var readPositionPercent: Int?
    /// Cumulative foreground time on this article (ms). Powers the
    /// "you've read this for Xm" indicator in the detail header.
    var timeSpentMsTotal: Int?
    /// Most recent foreground engagement timestamp (epoch ms). Useful
    /// for "last opened 2 days ago" copy without a separate query.
    var lastReadAt: Int?
}

struct CompanionArticle: Codable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: Int?
    let fetchedAt: Int?
    var contentHtml: String?
    var contentText: String?
    var excerpt: String?
    var wordCount: Int?
    var isRead: Int?
    var savedAt: String?
    // Deep-fetch tracking (populated after 0009 migration)
    var lastFetchAttemptAt: Int?
    var fetchAttemptCount: Int?
    var lastFetchError: String?

    var isReadBool: Bool { isRead == 1 }

    var hasContent: Bool {
        (contentHtml?.isEmpty == false) || (contentText?.isEmpty == false)
    }
}

struct FetchContentResult: Codable {
    let articleId: String
    let contentHtml: String?
    let contentText: String?
    let excerpt: String?
    let wordCount: Int?
    let imageUrl: String?
    let extractionMethod: String?
    let extractionQuality: Double?
    let lastFetchAttemptAt: Int?
    let lastFetchError: String?
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
    // Per-feed user controls
    var paused: Bool?
    var maxArticlesPerDay: Int?
    var minScore: Int?
    // Feed scraping
    var scrapeMode: String?
    var scrapeProvider: String?
    var feedType: String?
    var avgExtractionQuality: Double?
    var scrapeArticleCount: Int?
    var scrapeErrorCount: Int?
    var lastScrapeError: String?

    var disabledBool: Bool { disabled == 1 }
}

extension CompanionFeed {
    /// ETag derived from the three mutable subscription fields.
    ///
    /// Mirrors the server's `subscriptionEtag()` byte-for-byte so that
    /// `If-Match` comparisons succeed when the row is unchanged.
    ///
    /// `paused` defaults to `false` when nil (matching the server INSERT
    /// default of 0). `minScore` is **not** defaulted — nil means "unset"
    /// and the server distinguishes that from 0.
    ///
    /// NOTE: The save sheet initialises `minScore` as `feed.minScore ?? 0`,
    /// which collapses nil → 0 on the device side. This means the device may
    /// send etag `n0` while the server has `n`. The 412 conflict-resolution
    /// path handles this gracefully. See spec edge case 6 for details.
    // FIXME: nil minScore vs 0 conflation — see spec edge case 6.
    var settingsEtag: String {
        FeedSettingsETag.compute(
            paused: paused ?? false,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore
        )
    }
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
    /// Server filters to last_read_at IS NOT NULL and orders DESC.
    /// Used by the Read history surface in Library.
    case recentReads = "recent_reads"

    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .score: "Best fit"
        case .unreadFirst: "Unread first"
        case .recentReads: "Recently read"
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
    let resume: CompanionResumeReading?
}

struct CompanionResumeReading: Codable {
    let articleId: String
    let title: String?
    let canonicalUrl: String?
    let imageUrl: String?
    let positionPercent: Int
    let updatedAt: Int
}

// MARK: - Brief history

struct CompanionBriefSummary: Codable, Identifiable {
    let id: String
    let editionKind: String       // "morning" | "evening" | "ondemand"
    let editionSlot: String
    let timezone: String
    let generatedAt: Int
    let windowStart: Int
    let windowEnd: Int
    let scoreCutoff: Int
    let bullets: [CompanionNewsBrief.Bullet]
    let sourceArticleIds: [String]
    /// Tag id this brief was filtered to. Nil for the all-news brief.
    let topicTagId: String?
    /// Joined tag name from the server response — saves the iOS side a
    /// second tag lookup when rendering history rows.
    let topicTagName: String?
}

struct CompanionBriefDetail: Codable, Identifiable {
    struct SourceArticle: Codable, Identifiable {
        let id: String
        let title: String?
        let canonicalUrl: String?
    }

    let id: String
    let editionKind: String
    let editionSlot: String
    let timezone: String
    let generatedAt: Int
    let windowStart: Int
    let windowEnd: Int
    let scoreCutoff: Int
    let bullets: [CompanionNewsBrief.Bullet]
    let sourceArticleIds: [String]
    let sourceArticles: [SourceArticle]
    let topicTagId: String?
    let topicTagName: String?
}

struct CompanionBriefHistoryPayload: Codable {
    let briefs: [CompanionBriefSummary]
    let nextBefore: Int?
}

struct CompanionTodayStats: Codable {
    let unreadTotal: Int
    let newToday: Int
    let highFitUnread: Int
}

/// Weekly reading insights from `GET /api/insights/weekly`. The server
/// caches one snapshot per user per week so calling this is cheap; if no
/// AI provider is configured the backend returns a fallback narrative
/// derived from the structured stats below. Inner `data` field is
/// aliased to `stats` here so call sites read `insight.stats.articlesRead`
/// instead of the awkward `insight.data.data.articlesRead`.
struct CompanionWeeklyInsight: Codable {
    let text: String
    let stats: Stats?
    let generatedAt: Int

    struct Stats: Codable {
        let articlesRead: Int
        let topTopics: [Topic]
        let topFeeds: [Feed]

        struct Topic: Codable, Hashable {
            let name: String
            let cnt: Int
        }

        struct Feed: Codable, Hashable {
            let title: String
            let cnt: Int
        }
    }

    /// Only `stats` needs an explicit alias — APIClient's decoder uses
    /// `.convertFromSnakeCase`, which already turns JSON `generated_at`
    /// into `generatedAt` before key lookup. Adding a snake_case
    /// rawValue here would silently mis-match the converted key.
    enum CodingKeys: String, CodingKey {
        case text
        case stats = "data"
        case generatedAt
    }
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
    /// "headlines" | "summary" | "deep" — controls bullet count + words
    /// per bullet. Server reads this from the `newsBriefDepth` setting
    /// row; iOS defaults to "summary" when the row is missing so older
    /// payloads decode without breaking.
    var depth: String?
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
    // Backend migration 0019. Defaults to 'text' when absent so older
    // captured payloads still decode. Recognized values:
    //   text | brief_seed | tool_result | system_note
    var messageKind: String?

    var kind: String { messageKind ?? "text" }
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

// MARK: - AI Usage

struct UsageSummaryResponse: Codable {
    let daily: UsageBucket
    let weekly: UsageBucket
    let tier: String?
    let allowOverages: Bool
}

struct UsageBucket: Codable {
    let used: Int
    let limit: Int
}

// MARK: - AI Assistant

struct AssistantThreadSummary: Codable, Identifiable {
    let id: String
    let title: String?
    let lastMessage: String?
    let updatedAt: Int
    let messageCount: Int
}

// MARK: - Collections

struct CompanionCollection: Codable, Identifiable {
    let id: String
    var name: String
    var description: String?
    var color: String?
    var icon: String?
    var position: Int?
    var articleCount: Int?
    let createdAt: Int?
    var updatedAt: Int?
}

struct CompanionCollectionDetail: Codable {
    let collection: CompanionCollection
    let articles: [CompanionArticleListItem]
}

struct CompanionCollectionArticleResponse: Codable {
    let collectionId: String
    let articleId: String
    let position: Int
}

// MARK: - Highlights

struct CompanionHighlight: Codable, Identifiable {
    let id: String
    let articleId: String
    let selectedText: String
    let blockIndex: Int?
    let textOffset: Int?
    let textLength: Int?
    var note: String?
    var color: String?
    let createdAt: Int?
    var updatedAt: Int?
}

// MARK: - Annotations

struct CompanionAnnotation: Codable, Identifiable {
    let id: String
    let articleId: String
    var content: String
    let createdAt: Int?
    var updatedAt: Int?
}
