import Foundation
import NebularNewsKit

enum SupabaseManagerError: LocalizedError {
    case notAuthenticated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .invalidResponse:
            return "The server returned an unexpected response."
        }
    }
}

struct SupabaseArticleRow: Decodable {
    let id: String
    let canonicalUrl: String?
    let imageUrl: String?
    let title: String?
    let author: String?
    let publishedAt: String?
    let fetchedAt: String?
    let excerpt: String?
    let articleSummaries: [SummaryRow]?
    let articleReadState: [ReadStateRow]?
    let articleReactions: [ReactionRow]?
    let articleScores: [ScoreRow]?
    let articleSources: [SourceRow]?
    let articleTags: [ArticleTagRow]?

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalUrl = "canonical_url"
        case imageUrl = "image_url"
        case title, author
        case publishedAt = "published_at"
        case fetchedAt = "fetched_at"
        case excerpt
        case articleSummaries = "article_summaries"
        case articleReadState = "article_read_state"
        case articleReactions = "article_reactions"
        case articleScores = "article_scores"
        case articleSources = "article_sources"
        case articleTags = "article_tags"
    }

    func toArticleListItem() -> CompanionArticleListItem {
        let readState = articleReadState?.first
        let reaction = articleReactions?.first
        let score = articleScores?.first
        let source = articleSources?.first
        let tags = articleTags?.compactMap { $0.tags.map { CompanionTag(id: $0.id, name: $0.name) } }

        return CompanionArticleListItem(
            id: id,
            canonicalUrl: canonicalUrl,
            imageUrl: imageUrl,
            title: title,
            author: author,
            publishedAt: publishedAt.flatMap { timestampMillis($0) },
            fetchedAt: fetchedAt.flatMap { timestampMillis($0) },
            excerpt: excerpt,
            summaryText: articleSummaries?.first?.summaryText,
            isRead: (readState?.isRead == true) ? 1 : 0,
            reactionValue: reaction?.value,
            reactionReasonCodes: nil,
            score: score?.score,
            scoreLabel: score?.label,
            scoreStatus: score?.scoreStatus,
            scoreConfidence: score?.confidence.map { Double($0) },
            sourceName: source?.feeds?.title,
            sourceFeedId: source?.feedId,
            tags: tags
        )
    }
}

struct SupabaseArticleDetailRow: Decodable {
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
    let articleSummaries: [SummaryRow]?
    let articleKeyPoints: [KeyPointsRow]?
    let articleReadState: [ReadStateRow]?
    let articleReactions: [ReactionRow]?
    let articleScores: [ScoreRow]?
    let articleSources: [DetailSourceRow]?
    let articleTags: [ArticleTagRow]?
    let articleTagSuggestions: [TagSuggestionRow]?

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalUrl = "canonical_url"
        case imageUrl = "image_url"
        case title, author
        case publishedAt = "published_at"
        case fetchedAt = "fetched_at"
        case contentHtml = "content_html"
        case contentText = "content_text"
        case excerpt
        case wordCount = "word_count"
        case articleSummaries = "article_summaries"
        case articleKeyPoints = "article_key_points"
        case articleReadState = "article_read_state"
        case articleReactions = "article_reactions"
        case articleScores = "article_scores"
        case articleSources = "article_sources"
        case articleTags = "article_tags"
        case articleTagSuggestions = "article_tag_suggestions"
    }

    func toDetailPayload() -> ArticleDetailPayload {
        let readState = articleReadState?.first
        let reaction = articleReactions?.first
        let score = articleScores?.first
        let summary = articleSummaries?.first
        let keyPoints = articleKeyPoints?.first
        let tags = articleTags?.compactMap { $0.tags.map { CompanionTag(id: $0.id, name: $0.name) } } ?? []
        let tagSuggestions = articleTagSuggestions?.map { suggestion in
            CompanionTagSuggestion(id: suggestion.id, name: suggestion.tagName, confidence: suggestion.confidence.map { Double($0) })
        } ?? []

        let sources = articleSources?.map { source in
            CompanionSource(
                feedId: source.feedId,
                feedTitle: source.feeds?.title,
                siteUrl: source.feeds?.siteUrl,
                feedUrl: source.feeds?.url,
                reputation: nil,
                feedbackCount: nil
            )
        } ?? []

        return ArticleDetailPayload(
            article: CompanionArticle(
                id: id,
                canonicalUrl: canonicalUrl,
                imageUrl: imageUrl,
                title: title,
                author: author,
                publishedAt: publishedAt.flatMap { timestampMillis($0) },
                fetchedAt: fetchedAt.flatMap { timestampMillis($0) },
                contentHtml: contentHtml,
                contentText: contentText,
                excerpt: excerpt,
                wordCount: wordCount,
                isRead: (readState?.isRead == true) ? 1 : 0,
                savedAt: readState?.savedAt
            ),
            summary: summary.map { row in
                CompanionArticleSummary(
                    summaryText: row.summaryText,
                    provider: row.provider,
                    model: row.model,
                    createdAt: row.createdAt.flatMap { timestampMillis($0) }
                )
            },
            keyPoints: keyPoints.map { row in
                CompanionKeyPoints(
                    keyPointsJson: row.keyPointsJson,
                    provider: row.provider,
                    model: row.model,
                    createdAt: row.createdAt.flatMap { timestampMillis($0) }
                )
            },
            score: score.map { row in
                CompanionScore(
                    score: row.score,
                    label: row.label,
                    reasonText: row.reasonText,
                    evidenceJson: row.evidenceJson,
                    createdAt: row.createdAt.flatMap { timestampMillis($0) },
                    source: row.scoringMethod,
                    status: row.scoreStatus,
                    confidence: row.confidence.map { Double($0) },
                    preferenceConfidence: row.preferenceConfidence.map { Double($0) },
                    weightedAverage: row.weightedAverage.map { Double($0) }
                )
            },
            feedback: [],
            reaction: reaction.map { row in
                CompanionReaction(
                    articleId: row.articleId,
                    feedId: nil,
                    value: row.value ?? 0,
                    createdAt: row.createdAt.flatMap { timestampMillis($0) },
                    reasonCodes: nil
                )
            },
            preferredSource: sources.first,
            sources: sources,
            tags: tags,
            tagSuggestions: tagSuggestions
        )
    }
}

struct SummaryRow: Decodable {
    let summaryText: String?
    let provider: String?
    let model: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case summaryText = "summary_text"
        case provider, model
        case createdAt = "created_at"
    }
}

struct KeyPointsRow: Decodable {
    let keyPointsJson: String?
    let provider: String?
    let model: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case keyPointsJson = "key_points_json"
        case provider, model
        case createdAt = "created_at"
    }
}

struct ReadStateRow: Decodable {
    let isRead: Bool?
    let savedAt: String?

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case savedAt = "saved_at"
    }
}

struct ReactionRow: Decodable {
    let id: String?
    let articleId: String?
    let value: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case value
        case createdAt = "created_at"
    }
}

struct ScoreRow: Decodable {
    let score: Int?
    let label: String?
    let reasonText: String?
    let evidenceJson: String?
    let createdAt: String?
    let scoreStatus: String?
    let scoringMethod: String?
    let confidence: Float?
    let preferenceConfidence: Float?
    let weightedAverage: Float?

    enum CodingKeys: String, CodingKey {
        case score, label
        case reasonText = "reason_text"
        case evidenceJson = "evidence_json"
        case createdAt = "created_at"
        case scoreStatus = "score_status"
        case scoringMethod = "scoring_method"
        case confidence
        case preferenceConfidence = "preference_confidence"
        case weightedAverage = "weighted_average"
    }
}

struct SourceRow: Decodable {
    let feedId: String?
    let feeds: FeedRef?

    enum CodingKeys: String, CodingKey {
        case feedId = "feed_id"
        case feeds
    }
}

struct FeedRef: Decodable {
    let id: String
    let title: String?
}

struct DetailSourceRow: Decodable {
    let feedId: String?
    let feeds: DetailFeedRef?

    enum CodingKeys: String, CodingKey {
        case feedId = "feed_id"
        case feeds
    }
}

struct DetailFeedRef: Decodable {
    let id: String
    let title: String?
    let siteUrl: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case siteUrl = "site_url"
        case url
    }
}

struct ArticleTagRow: Decodable {
    let tagId: String?
    let tags: TagRef?

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tags
    }
}

struct TagRef: Decodable {
    let id: String
    let name: String
}

struct TagSuggestionRow: Decodable {
    let id: String
    let tagName: String
    let confidence: Float?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case confidence
    }
}

struct SupabaseTagRow: Decodable {
    let id: String
    let name: String
}

struct SupabaseTagWithCountRow: Decodable {
    let id: String
    let name: String
    let slug: String?
    let color: String?
    let description: String?
    let articleTags: [CountRow]?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, color, description
        case articleTags = "article_tags"
    }

    func toTagWithCount() -> CompanionTagWithCount {
        CompanionTagWithCount(
            id: id,
            name: name,
            slug: slug,
            color: color,
            description: description,
            articleCount: articleTags?.first?.count ?? 0
        )
    }
}

struct CountRow: Decodable {
    let count: Int
}

struct SupabaseArticleTagJoinRow: Decodable {
    let tagId: String?
    let tags: TagRef?

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tags
    }
}

struct SupabaseFeedRow: Decodable {
    let feedId: String?
    let feeds: FeedDetailRow?
    let paused: Bool?
    let maxArticlesPerDay: Int?
    let minScore: Int?

    enum CodingKeys: String, CodingKey {
        case feedId = "feed_id"
        case feeds
        case paused
        case maxArticlesPerDay = "max_articles_per_day"
        case minScore = "min_score"
    }

    func toCompanionFeed() -> CompanionFeed? {
        guard let feed = feeds else { return nil }
        return CompanionFeed(
            id: feed.id,
            url: feed.url,
            title: feed.title,
            siteUrl: feed.siteUrl,
            lastPolledAt: feed.lastPolledAt.flatMap { timestampMillis($0) },
            nextPollAt: feed.nextPollAt.flatMap { timestampMillis($0) },
            errorCount: feed.errorCount,
            disabled: feed.disabled == true ? 1 : 0,
            articleCount: feed.articleSources?.first?.count,
            paused: paused,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore,
            scrapeMode: feed.scrapeMode,
            scrapeProvider: feed.scrapeProvider,
            feedType: feed.feedType,
            avgExtractionQuality: feed.avgExtractionQuality,
            scrapeArticleCount: feed.scrapeArticleCount,
            scrapeErrorCount: feed.scrapeErrorCount,
            lastScrapeError: feed.lastScrapeError
        )
    }
}

struct FeedDetailRow: Decodable {
    let id: String
    let url: String
    let title: String?
    let siteUrl: String?
    let lastPolledAt: String?
    let nextPollAt: String?
    let errorCount: Int?
    let disabled: Bool?
    let scrapeMode: String?
    let scrapeProvider: String?
    let feedType: String?
    let avgExtractionQuality: Double?
    let scrapeArticleCount: Int?
    let scrapeErrorCount: Int?
    let lastScrapeError: String?
    let articleSources: [CountRow]?

    enum CodingKeys: String, CodingKey {
        case id, url, title
        case siteUrl = "site_url"
        case lastPolledAt = "last_polled_at"
        case nextPollAt = "next_poll_at"
        case errorCount = "error_count"
        case disabled
        case scrapeMode = "scrape_mode"
        case scrapeProvider = "scrape_provider"
        case feedType = "feed_type"
        case avgExtractionQuality = "avg_extraction_quality"
        case scrapeArticleCount = "scrape_article_count"
        case scrapeErrorCount = "scrape_error_count"
        case lastScrapeError = "last_scrape_error"
        case articleSources = "article_sources"
    }
}

struct SupabaseBasicFeedRow: Decodable {
    let id: String
}

struct SupabaseReactionRow: Decodable {
    let id: String?
    let articleId: String?
    let value: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case value
        case createdAt = "created_at"
    }
}

struct SupabaseUserSettingRow: Decodable {
    let key: String
    let value: String
}

struct SupabaseChatThreadRow: Decodable {
    let id: String
    let articleId: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case articleId = "article_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SupabaseChatMessageRow: Decodable {
    let id: String
    let threadId: String
    let role: String
    let content: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case role, content
        case createdAt = "created_at"
    }
}

struct ReadStateUpsert: Encodable {
    let articleId: String
    let userId: String
    let isRead: Bool
    let readAt: String?

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case isRead = "is_read"
        case readAt = "read_at"
    }
}

struct SaveUpsert: Encodable {
    let articleId: String
    let userId: String
    let savedAt: String?

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case savedAt = "saved_at"
    }
}

struct ReactionUpsert: Encodable {
    let articleId: String
    let userId: String
    let value: Int

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case value
    }
}

struct ReactionReasonInsert: Encodable {
    let articleId: String
    let userId: String
    let reasonCode: String

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case reasonCode = "reason_code"
    }
}

struct TagInsert: Encodable {
    let name: String
    let nameNormalized: String
    let slug: String

    enum CodingKeys: String, CodingKey {
        case name
        case nameNormalized = "name_normalized"
        case slug
    }
}

struct ArticleTagInsert: Encodable {
    let articleId: String
    let tagId: String
    let userId: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case tagId = "tag_id"
        case userId = "user_id"
        case source
    }
}

struct FeedInsert: Encodable {
    let url: String
}

struct FeedSubscriptionInsert: Encodable {
    let userId: String
    let feedId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case feedId = "feed_id"
    }
}

struct DeviceTokenUpsert: Encodable {
    let userId: String
    let token: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case token, platform
    }
}

struct ChatThreadInsert: Encodable {
    let articleId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
    }
}

struct ChatMessageInsert: Encodable {
    let threadId: String
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case role, content
    }
}

struct UserSettingUpsert: Encodable {
    let userId: String
    let key: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case key, value
    }
}

struct OPMLImportResponse: Decodable {
    let added: Int
}

struct OPMLExportResponse: Decodable {
    let opml: String
}

typealias ArticlesPayload = CompanionArticlesPayload
typealias ArticleDetailPayload = CompanionArticleDetailPayload

struct ReactionResponse {
    let articleId: String
    let value: Int
    let createdAt: String?
    let reasonCodes: [String]
}

struct SaveResponse {
    let articleId: String
    let saved: Bool
    let savedAt: String?
}

func timestampMillis(_ isoString: String) -> Int? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    return nil
}

struct RescoreRequest: Encodable {
    let userId: String
    let rescore: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case rescore
    }
}

struct BriefBulletDTO: Decodable {
    let text: String
    let sourceArticleIds: [String]?

    enum CodingKeys: String, CodingKey {
        case text
        case sourceArticleIds = "source_article_ids"
    }
}

typealias ReadFilter = CompanionReadFilter
typealias SortOrder = CompanionSortOrder
