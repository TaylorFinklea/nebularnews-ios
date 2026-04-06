import Foundation
import NebularNewsKit
import os
import Supabase

struct ArticleService: Sendable {
    let client: SupabaseClient
    private let logger: Logger

    init(client: SupabaseClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    private var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    func fetchArticles(
        query: String = "",
        offset: Int = 0,
        limit: Int = 20,
        read: ReadFilter = .all,
        minScore: Int? = nil,
        sort: SortOrder = .newest,
        sinceDays: Int? = nil,
        tag: String? = nil,
        saved: Bool = false
    ) async throws -> ArticlesPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        var request = client.from("articles")
            .select("""
                id, canonical_url, image_url, title, author, published_at, fetched_at, excerpt,
                article_summaries(summary_text),
                article_read_state!left(is_read, saved_at),
                article_reactions!left(value),
                article_scores!left(score, label, score_status, confidence),
                article_sources!inner(feed_id, feeds!inner(id, title)),
                article_tags(tag_id, tags(id, name))
            """)

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request = request.textSearch("search_vector", query: query)
        }

        let readFilterClientSide = read
        let savedFilterClientSide = saved

        if let minScore {
            request = request.gte("article_scores.score", value: minScore)
        }

        if let sinceDays {
            let cutoff = Date().addingTimeInterval(-Double(sinceDays) * 86400)
            request = request.gte("fetched_at", value: cutoff.ISO8601Format())
        }

        if let tag {
            request = request.eq("article_tags.tag_id", value: tag)
        }

        let effectiveLimit = max(limit, 1)
        let fetchLimit = effectiveLimit * 4
        let feedLimits = try await getFeedLimits(userId: userId)

        let sorted: PostgrestTransformBuilder
        switch sort {
        case .newest:
            sorted = request.order("fetched_at", ascending: false)
        case .oldest:
            sorted = request.order("fetched_at", ascending: true)
        case .score:
            sorted = request.order("fetched_at", ascending: false)
        case .unreadFirst:
            sorted = request.order("fetched_at", ascending: false)
        }

        let finalRequest = sorted.range(from: offset, to: offset + fetchLimit - 1)
        var articles: [SupabaseArticleRow] = try await finalRequest.execute().value

        switch readFilterClientSide {
        case .unread:
            articles = articles.filter { $0.articleReadState?.first?.isRead != true }
        case .read:
            articles = articles.filter { $0.articleReadState?.first?.isRead == true }
        case .all:
            break
        }

        if savedFilterClientSide {
            articles = articles.filter { $0.articleReadState?.first?.savedAt != nil }
        }

        if !savedFilterClientSide && !feedLimits.isEmpty {
            var feedCounts: [String: Int] = [:]
            articles = articles.filter { article in
                guard let source = article.articleSources?.first,
                      let feedId = source.feedId ?? source.feeds?.id else { return true }
                guard let limit = feedLimits[feedId] else { return true }
                let count = feedCounts[feedId, default: 0]
                if count >= limit { return false }
                feedCounts[feedId] = count + 1
                return true
            }
        }

        let postFilterCount = articles.count
        let trimmed = Array(articles.prefix(effectiveLimit))
        let items = trimmed.map { $0.toArticleListItem() }

        let hasClientFilters = readFilterClientSide != .all || savedFilterClientSide || !feedLimits.isEmpty
        let total: Int
        if hasClientFilters {
            if postFilterCount < fetchLimit {
                total = offset + postFilterCount
            } else {
                total = offset + postFilterCount + effectiveLimit
            }
        } else {
            let countResponse = try await client.from("articles")
                .select("id", head: true, count: .exact)
                .execute()
            total = countResponse.count ?? (offset + items.count)
        }

        return ArticlesPayload(
            articles: items,
            total: total,
            limit: limit,
            offset: offset
        )
    }

    func fetchArticle(id: String) async throws -> ArticleDetailPayload {
        guard await currentUserId != nil else { throw SupabaseManagerError.notAuthenticated }

        let article: SupabaseArticleDetailRow = try await client.from("articles")
            .select("""
                id, canonical_url, image_url, title, author, published_at, fetched_at,
                content_html, content_text, excerpt, word_count,
                article_summaries(summary_text, provider, model, created_at),
                article_key_points(key_points_json, provider, model, created_at),
                article_read_state!left(is_read, saved_at),
                article_reactions!left(id, article_id, value, created_at),
                article_scores!left(score, label, reason_text, evidence_json, created_at, score_status, scoring_method, confidence, preference_confidence, weighted_average),
                article_sources(feed_id, feeds(id, title, site_url, url)),
                article_tags(tag_id, tags(id, name)),
                article_tag_suggestions(id, tag_name, confidence)
            """)
            .eq("id", value: id)
            .single()
            .execute()
            .value

        return article.toDetailPayload()
    }

    func setRead(articleId: String, isRead: Bool) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("article_read_state")
            .upsert(ReadStateUpsert(
                articleId: articleId,
                userId: userId.uuidString,
                isRead: isRead,
                readAt: isRead ? Date().ISO8601Format() : nil
            ), onConflict: "article_id,user_id")
            .execute()
    }

    func saveArticle(id: String, saved: Bool) async throws -> SaveResponse {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let savedAt = saved ? Date().ISO8601Format() : nil

        try await client.from("article_read_state")
            .upsert(SaveUpsert(
                articleId: id,
                userId: userId.uuidString,
                savedAt: savedAt
            ), onConflict: "article_id,user_id")
            .execute()

        return SaveResponse(articleId: id, saved: saved, savedAt: savedAt)
    }

    func dismissArticle(id: String) async throws {
        try await setRead(articleId: id, isRead: true)
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async throws -> ReactionResponse {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let reaction: SupabaseReactionRow = try await client.from("article_reactions")
            .upsert(ReactionUpsert(
                articleId: articleId,
                userId: userId.uuidString,
                value: value
            ), onConflict: "article_id,user_id")
            .select()
            .single()
            .execute()
            .value

        try await client.from("article_reaction_reasons")
            .delete()
            .eq("article_id", value: articleId)
            .eq("user_id", value: userId.uuidString)
            .execute()

        if !reasonCodes.isEmpty {
            let reasons = reasonCodes.map { code in
                ReactionReasonInsert(
                    articleId: articleId,
                    userId: userId.uuidString,
                    reasonCode: code
                )
            }
            try await client.from("article_reaction_reasons")
                .insert(reasons)
                .execute()
        }

        let rescoreUserId = userId.uuidString
        let rescoreClient = client
        let rescoreLogger = logger
        Task.detached {
            do {
                try await rescoreClient.functions.invoke(
                    "score-articles",
                    options: FunctionInvokeOptions(
                        body: RescoreRequest(userId: rescoreUserId, rescore: true)
                    )
                )
            } catch {
                rescoreLogger.error("Failed to trigger background article rescore for user \(rescoreUserId): \(error.localizedDescription)")
            }
        }

        return ReactionResponse(
            articleId: articleId,
            value: value,
            createdAt: reaction.createdAt,
            reasonCodes: reasonCodes
        )
    }

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let existingTags: [SupabaseTagRow] = try await client.from("tags")
            .select("id, name")
            .ilike("name_normalized", pattern: name.lowercased())
            .execute()
            .value

        let tagId: String
        if let existing = existingTags.first {
            tagId = existing.id
        } else {
            let slug = name.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let newTag: SupabaseTagRow = try await client.from("tags")
                .insert(TagInsert(name: name, nameNormalized: name.lowercased(), slug: slug))
                .select("id, name")
                .single()
                .execute()
                .value
            tagId = newTag.id
        }

        try await client.from("article_tags")
            .upsert(ArticleTagInsert(
                articleId: articleId,
                tagId: tagId,
                userId: userId.uuidString,
                source: "manual"
            ), onConflict: "article_id,tag_id,user_id")
            .execute()

        return try await fetchArticleTags(articleId: articleId)
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        guard await currentUserId != nil else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("article_tags")
            .delete()
            .eq("article_id", value: articleId)
            .eq("tag_id", value: tagId)
            .execute()

        return try await fetchArticleTags(articleId: articleId)
    }

    func fetchTags(query: String? = nil, limit: Int? = nil) async throws -> [CompanionTagWithCount] {
        var request = client.from("tags")
            .select("id, name, slug, color, description, article_tags(count)")

        if let query, !query.isEmpty {
            request = request.ilike("name", value: "%\(query)%")
        }

        var finalReq = request.order("name")
        if let limit {
            finalReq = finalReq.limit(limit)
        }

        let rows: [SupabaseTagWithCountRow] = try await finalReq.execute().value
        return rows.map { $0.toTagWithCount() }
    }

    func createTag(name: String) async throws -> CompanionTagWithCount {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let tag: SupabaseTagRow = try await client.from("tags")
            .insert(TagInsert(name: name, nameNormalized: name.lowercased(), slug: slug))
            .select("id, name")
            .single()
            .execute()
            .value

        return CompanionTagWithCount(
            id: tag.id,
            name: tag.name,
            slug: slug,
            color: nil,
            description: nil,
            articleCount: 0
        )
    }

    func deleteTag(id: String) async throws {
        try await client.from("tags")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchToday() async throws -> CompanionTodayPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let articleSelect = """
            id, canonical_url, image_url, title, author, published_at, fetched_at, excerpt,
            article_summaries(summary_text),
            article_read_state!left(is_read, saved_at),
            article_reactions!left(value),
            article_scores!left(score, label, score_status, confidence),
            article_sources!inner(feed_id, feeds!inner(id, title)),
            article_tags(tag_id, tags(id, name))
        """

        let feedLimits = try await getFeedLimits(userId: userId)

        let allRecent: [SupabaseArticleRow] = try await client.from("articles")
            .select(articleSelect)
            .order("fetched_at", ascending: false)
            .limit(500)
            .execute()
            .value

        var feedCounts: [String: Int] = [:]
        let visible = allRecent.filter { article in
            guard !feedLimits.isEmpty else { return true }
            guard let source = article.articleSources?.first,
                  let feedId = source.feedId ?? source.feeds?.id else { return true }
            guard let limit = feedLimits[feedId] else { return true }
            let count = feedCounts[feedId, default: 0]
            if count >= limit { return false }
            feedCounts[feedId] = count + 1
            return true
        }

        let unreadVisible = visible.filter { $0.articleReadState?.first?.isRead != true }
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let oneDayAgoStr = oneDayAgo.ISO8601Format()
        let newTodayVisible = visible.filter { row in
            guard let fetchedAt = row.fetchedAt else { return false }
            return fetchedAt >= oneDayAgoStr
        }
        let newTodayUnread = newTodayVisible.filter { $0.articleReadState?.first?.isRead != true }
        let highFitUnread = unreadVisible.filter { row in
            guard let score = row.articleScores?.first?.score else { return false }
            return score >= 4
        }

        let hero = highFitUnread.first?.toArticleListItem()
        let upNext = unreadVisible
            .map { $0.toArticleListItem() }
            .filter { $0.id != hero?.id }
            .prefix(6)
            .map { $0 }

        let stats = CompanionTodayStats(
            unreadTotal: unreadVisible.count,
            newToday: newTodayUnread.count,
            highFitUnread: highFitUnread.count
        )

        let newsBrief = await fetchLatestNewsBrief(userId: userId)

        return CompanionTodayPayload(
            hero: hero,
            upNext: Array(upNext),
            stats: stats,
            newsBrief: newsBrief
        )
    }

    private func fetchArticleTags(articleId: String) async throws -> [CompanionTag] {
        let rows: [SupabaseArticleTagJoinRow] = try await client.from("article_tags")
            .select("tag_id, tags(id, name)")
            .eq("article_id", value: articleId)
            .execute()
            .value
        return rows.compactMap { row in
            guard let tag = row.tags else { return nil }
            return CompanionTag(id: tag.id, name: tag.name)
        }
    }

    private func getFeedLimits(userId: UUID) async throws -> [String: Int] {
        struct FeedLimitRow: Decodable {
            let feedId: String
            let maxArticlesPerDay: Int?

            enum CodingKeys: String, CodingKey {
                case feedId = "feed_id"
                case maxArticlesPerDay = "max_articles_per_day"
            }
        }

        let rows: [FeedLimitRow] = try await client.from("user_feed_subscriptions")
            .select("feed_id, max_articles_per_day")
            .eq("user_id", value: userId.uuidString)
            .not("max_articles_per_day", operator: .is, value: "null")
            .execute()
            .value
        var limits: [String: Int] = [:]
        for row in rows {
            if let max = row.maxArticlesPerDay, max > 0 {
                limits[row.feedId] = max
            }
        }
        return limits
    }

    private func fetchLatestNewsBrief(userId: UUID) async -> CompanionNewsBrief? {
        struct BriefRow: Decodable {
            let id: String
            let editionType: String
            let briefText: String
            let articleIdsJson: String?
            let createdAt: String?

            enum CodingKeys: String, CodingKey {
                case id
                case editionType = "edition_type"
                case briefText = "brief_text"
                case articleIdsJson = "article_ids_json"
                case createdAt = "created_at"
            }
        }

        guard let row: BriefRow = try? await client.from("news_brief_editions")
            .select("id, edition_type, brief_text, article_ids_json, created_at")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .single()
            .execute()
            .value
        else { return nil }

        let createdAtMillis = row.createdAt.flatMap { timestampMillis($0) }
        let isStale: Bool
        if let ms = createdAtMillis {
            isStale = Date().timeIntervalSince1970 * 1000 - Double(ms) > 12 * 3_600_000
        } else {
            isStale = true
        }

        let bullets: [CompanionNewsBrief.Bullet]
        if let data = row.briefText.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([BriefBulletDTO].self, from: data) {
            bullets = parsed.map { dto in
                CompanionNewsBrief.Bullet(
                    text: dto.text,
                    sources: (dto.sourceArticleIds ?? []).map { id in
                        CompanionNewsBrief.Bullet.Source(articleId: id, title: "", canonicalUrl: nil)
                    }
                )
            }
        } else {
            bullets = [CompanionNewsBrief.Bullet(text: row.briefText, sources: [])]
        }

        return CompanionNewsBrief(
            state: isStale ? "stale" : "ready",
            title: "News Brief",
            editionLabel: row.editionType.replacingOccurrences(of: "_", with: " ").capitalized,
            generatedAt: createdAtMillis,
            windowHours: 12,
            scoreCutoff: 3,
            bullets: bullets,
            nextScheduledAt: nil,
            stale: isStale
        )
    }
}
