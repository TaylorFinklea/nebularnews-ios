import Foundation
import NebularNewsKit
import Supabase

// MARK: - Supabase Manager

/// Central service that replaces MobileAPIClient with direct Supabase SDK calls.
///
/// Uses PostgREST for reads, direct table operations for writes, and
/// Supabase Edge Functions for AI-powered operations (enrichment, chat).
/// Auth is handled by the Supabase Auth module (Apple Sign In via ID token).
final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        guard let supabaseURL = URL(string: "https://vdjrclxeyjsqyqsjzjfj.supabase.co") else {
            preconditionFailure("Invalid Supabase URL")
        }
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkanJjbHhleWpzcXlxc2p6amZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NTk0OTIsImV4cCI6MjA5MDUzNTQ5Mn0.9j644tw6xud8GNW-J0X_sgtR_oyXGEoi59cN-O7wTHY",
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: "nebularnews://auth-callback"),
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    /// Current authenticated user ID, or nil if not signed in.
    var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    // MARK: - Auth

    /// Sign in with an Apple ID token from AuthenticationServices.
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func session() async throws -> Session {
        try await client.auth.session
    }

    // MARK: - Articles

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

        // Build the query selecting articles with their source feed info
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

        // Apply user-scoped filters via RLS or explicit filters
        // RLS policies handle user scoping on read_state, reactions, scores

        // Search filter
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request = request.textSearch("search_vector", query: query)
        }

        // Read filter — PostgREST can't do OR across joined tables,
        // so we filter client-side after fetching
        let readFilterClientSide = read

        // Saved filter — PostgREST can't filter on left-joined columns,
        // so we filter client-side after fetching
        let savedFilterClientSide = saved

        // Score filter
        if let minScore {
            request = request.gte("article_scores.score", value: minScore)
        }

        // Time filter
        if let sinceDays {
            let cutoff = Date().addingTimeInterval(-Double(sinceDays) * 86400)
            request = request.gte("fetched_at", value: cutoff.ISO8601Format())
        }

        // Tag filter
        if let tag {
            request = request.eq("article_tags.tag_id", value: tag)
        }

        // Overfetch to compensate for client-side filtering (read state, saved, feed limits).
        // We fetch 4x the requested limit to ensure we have enough after filtering.
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

        // Apply filters client-side (PostgREST can't filter on left-joined columns)
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

        // Apply per-feed daily article limits
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

        // Trim to requested page size after all client-side filtering
        let postFilterCount = articles.count
        let trimmed = Array(articles.prefix(effectiveLimit))
        let items = trimmed.map { $0.toArticleListItem() }

        // Total: if client-side filters are active, use post-filter count
        // (server count doesn't reflect read/saved/feed-limit filters)
        let hasClientFilters = readFilterClientSide != .all || savedFilterClientSide || !feedLimits.isEmpty
        let total: Int
        if hasClientFilters {
            // If we got fewer than we fetched, we've seen everything
            if postFilterCount < fetchLimit {
                total = offset + postFilterCount
            } else {
                // Estimate: there are likely more beyond what we fetched
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
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let article: SupabaseArticleDetailRow = try await client.from("articles")
            .select("""
                id, canonical_url, image_url, title, author, published_at, fetched_at,
                content_html, content_text, excerpt, word_count,
                article_summaries(summary_text, provider, model, created_at),
                article_key_points(key_points_json, provider, model, created_at),
                article_read_state!left(is_read, saved_at),
                article_reactions!left(id, article_id, value, created_at),
                article_scores!left(score, label, reason_text, evidence_json, created_at, score_status, confidence, preference_confidence, weighted_average),
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
        // Mark as read + dismissed (we use read state since there's no dismiss column)
        try await setRead(articleId: id, isRead: true)
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async throws -> ReactionResponse {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        // Upsert the reaction
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

        // Delete old reason codes and insert new ones
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

        // Trigger re-scoring in the background so updated reaction data
        // feeds back into the algorithmic score engine.
        let rescoreUserId = userId.uuidString
        let rescoreClient = client
        Task.detached {
            try? await rescoreClient.functions.invoke(
                "score-articles",
                options: FunctionInvokeOptions(
                    body: RescoreRequest(userId: rescoreUserId, rescore: true)
                )
            )
        }

        return ReactionResponse(
            articleId: articleId,
            value: value,
            createdAt: reaction.createdAt,
            reasonCodes: reasonCodes
        )
    }

    // MARK: - Tags

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        // Find or create the tag
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

        // Create the article_tag association
        try await client.from("article_tags")
            .upsert(ArticleTagInsert(
                articleId: articleId,
                tagId: tagId,
                userId: userId.uuidString,
                source: "manual"
            ), onConflict: "article_id,tag_id,user_id")
            .execute()

        // Return updated tags for this article
        return try await fetchArticleTags(articleId: articleId)
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("article_tags")
            .delete()
            .eq("article_id", value: articleId)
            .eq("tag_id", value: tagId)
            .execute()

        return try await fetchArticleTags(articleId: articleId)
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

    /// Returns feed_id → max_articles_per_day for feeds that have a limit set.
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

    // MARK: - Feeds

    func fetchFeeds() async throws -> [CompanionFeed] {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let rows: [SupabaseFeedRow] = try await client.from("user_feed_subscriptions")
            .select("""
                feed_id, paused, max_articles_per_day, min_score,
                feeds(id, url, title, site_url, last_polled_at, next_poll_at, error_count, disabled, scrape_mode, scrape_provider, feed_type, avg_extraction_quality, scrape_article_count, scrape_error_count, last_scrape_error, article_sources(count))
            """)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        return rows.compactMap { $0.toCompanionFeed() }
    }

    func addFeed(url: String) async throws -> String {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        // Insert the feed (or get existing by URL)
        let existingFeeds: [SupabaseBasicFeedRow] = try await client.from("feeds")
            .select("id")
            .eq("url", value: url)
            .execute()
            .value

        let feedId: String
        if let existing = existingFeeds.first {
            feedId = existing.id
        } else {
            let newFeed: SupabaseBasicFeedRow = try await client.from("feeds")
                .insert(FeedInsert(url: url))
                .select("id")
                .single()
                .execute()
                .value
            feedId = newFeed.id
        }

        // Subscribe the user
        try await client.from("user_feed_subscriptions")
            .upsert(FeedSubscriptionInsert(userId: userId.uuidString, feedId: feedId), onConflict: "user_id,feed_id")
            .execute()

        return feedId
    }

    func deleteFeed(id: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        // Remove the subscription
        try await client.from("user_feed_subscriptions")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("feed_id", value: id)
            .execute()
    }

    func updateFeedSettings(feedId: String, paused: Bool? = nil, maxArticlesPerDay: Int? = nil, minScore: Int? = nil) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        var updates: [String: AnyJSON] = [
            "updated_at": AnyJSON.string(Date().ISO8601Format())
        ]
        if let paused {
            updates["paused"] = AnyJSON.bool(paused)
            updates["paused_at"] = paused ? AnyJSON.string(Date().ISO8601Format()) : AnyJSON.null
        }
        if let maxArticlesPerDay {
            updates["max_articles_per_day"] = maxArticlesPerDay > 0 ? AnyJSON.integer(maxArticlesPerDay) : AnyJSON.null
        }
        if let minScore {
            updates["min_score"] = minScore > 0 ? AnyJSON.integer(minScore) : AnyJSON.null
        }

        try await client.from("user_feed_subscriptions")
            .update(updates)
            .eq("user_id", value: userId.uuidString)
            .eq("feed_id", value: feedId)
            .execute()
    }

    func updateFeedScrapeConfig(feedId: String, scrapeMode: String, scrapeProvider: String?, feedType: String) async throws {
        var updates: [String: AnyJSON] = [
            "scrape_mode": AnyJSON.string(scrapeMode),
            "feed_type": AnyJSON.string(feedType),
            "updated_at": AnyJSON.string(Date().ISO8601Format())
        ]
        if let provider = scrapeProvider, !provider.isEmpty {
            updates["scrape_provider"] = AnyJSON.string(provider)
        } else {
            updates["scrape_provider"] = AnyJSON.null
        }
        try await client.from("feeds")
            .update(updates)
            .eq("id", value: feedId)
            .execute()
    }

    func importOPML(xml: String) async throws -> Int {
        let response: OPMLImportResponse = try await client.functions.invoke(
            "import-opml",
            options: FunctionInvokeOptions(
                body: ["opml": xml]
            )
        )
        return response.added
    }

    func exportOPML() async throws -> String {
        let response: OPMLExportResponse = try await client.functions.invoke(
            "export-opml",
            options: FunctionInvokeOptions(body: [:] as [String: String])
        )
        return response.opml
    }

    @discardableResult
    func triggerPull(cycles: Int = 1) async throws -> Void {
        _ = try await client.functions.invoke(
            "poll-feeds",
            options: FunctionInvokeOptions(
                body: ["cycles": cycles]
            )
        )
    }

    // MARK: - Today

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

        // Fetch a large batch of recent articles to compute accurate stats
        let allRecent: [SupabaseArticleRow] = try await client.from("articles")
            .select(articleSelect)
            .order("fetched_at", ascending: false)
            .limit(500)
            .execute()
            .value

        // Apply feed limits to get the user's actual visible articles
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

        // Compute stats from visible articles
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

        // Hero = highest scored unread article from last 7 days
        let hero = highFitUnread.first?.toArticleListItem()

        // Up next = recent unread, excluding hero
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

        // Fetch the most recent news brief for this user
        let newsBrief = await fetchLatestNewsBrief(userId: userId)

        return CompanionTodayPayload(
            hero: hero,
            upNext: Array(upNext),
            stats: stats,
            newsBrief: newsBrief
        )
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

        // Check staleness (older than 12 hours)
        let createdAtMillis = row.createdAt.flatMap { timestampMillis($0) }
        let isStale: Bool
        if let ms = createdAtMillis {
            isStale = Date().timeIntervalSince1970 * 1000 - Double(ms) > 12 * 3_600_000
        } else {
            isStale = true
        }

        // Parse bullets from brief_text JSON
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

    // MARK: - Settings

    func fetchSettings() async throws -> CompanionSettingsPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let rows: [SupabaseUserSettingRow] = try await client.from("user_settings")
            .select("key, value")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        var settings = CompanionSettingsPayload(
            pollIntervalMinutes: 15,
            summaryStyle: "concise",
            scoringMethod: "ai",
            newsBriefConfig: CompanionNewsBriefConfig(
                enabled: true,
                timezone: TimeZone.current.identifier,
                morningTime: "08:00",
                eveningTime: "17:00",
                lookbackHours: 12,
                scoreCutoff: 3
            ),
            upNextLimit: 6,
            retentionArchiveDays: 30,
            retentionDeleteDays: 90
        )

        for row in rows {
            switch row.key {
            case "pollIntervalMinutes":
                settings.pollIntervalMinutes = Int(row.value) ?? settings.pollIntervalMinutes
            case "summaryStyle":
                settings.summaryStyle = row.value
            case "scoringMethod":
                settings.scoringMethod = row.value
            case "upNextLimit":
                settings.upNextLimit = Int(row.value) ?? settings.upNextLimit
            case "retentionArchiveDays":
                settings.retentionArchiveDays = Int(row.value)
            case "retentionDeleteDays":
                settings.retentionDeleteDays = Int(row.value)
            case "newsBriefEnabled":
                settings.newsBriefConfig.enabled = row.value == "true"
            case "newsBriefTimezone":
                settings.newsBriefConfig.timezone = row.value
            case "newsBriefMorningTime":
                settings.newsBriefConfig.morningTime = row.value
            case "newsBriefEveningTime":
                settings.newsBriefConfig.eveningTime = row.value
            case "newsBriefLookbackHours":
                settings.newsBriefConfig.lookbackHours = Int(row.value) ?? settings.newsBriefConfig.lookbackHours
            case "newsBriefScoreCutoff":
                settings.newsBriefConfig.scoreCutoff = Int(row.value) ?? settings.newsBriefConfig.scoreCutoff
            default:
                break
            }
        }

        return settings
    }

    func updateSettings(_ settings: CompanionSettingsPayload) async throws -> CompanionSettingsPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let pairs: [(String, String)] = [
            ("pollIntervalMinutes", String(settings.pollIntervalMinutes)),
            ("summaryStyle", settings.summaryStyle),
            ("scoringMethod", settings.scoringMethod),
            ("upNextLimit", String(settings.upNextLimit)),
            ("retentionArchiveDays", String(settings.retentionArchiveDays ?? 30)),
            ("retentionDeleteDays", String(settings.retentionDeleteDays ?? 90)),
            ("newsBriefEnabled", settings.newsBriefConfig.enabled ? "true" : "false"),
            ("newsBriefTimezone", settings.newsBriefConfig.timezone),
            ("newsBriefMorningTime", settings.newsBriefConfig.morningTime),
            ("newsBriefEveningTime", settings.newsBriefConfig.eveningTime),
            ("newsBriefLookbackHours", String(settings.newsBriefConfig.lookbackHours)),
            ("newsBriefScoreCutoff", String(settings.newsBriefConfig.scoreCutoff))
        ]

        let upserts = pairs.map { (key, value) in
            UserSettingUpsert(userId: userId.uuidString, key: key, value: value)
        }

        try await client.from("user_settings")
            .upsert(upserts, onConflict: "user_id,key")
            .execute()

        return settings
    }

    // MARK: - Chat

    func fetchChat(articleId: String) async throws -> CompanionChatPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let threads: [SupabaseChatThreadRow] = try await client.from("chat_threads")
            .select("id, article_id, created_at, updated_at")
            .eq("article_id", value: articleId)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let thread = threads.first else {
            return CompanionChatPayload(thread: nil, messages: [])
        }

        let messages: [SupabaseChatMessageRow] = try await client.from("chat_messages")
            .select("id, thread_id, role, content, created_at")
            .eq("thread_id", value: thread.id)
            .order("created_at")
            .execute()
            .value

        let companionThread = CompanionChatThread(
            id: thread.id,
            articleId: thread.articleId,
            title: nil,
            createdAt: Int(thread.createdAt?.timeIntervalSince1970 ?? 0),
            updatedAt: Int(thread.updatedAt?.timeIntervalSince1970 ?? 0)
        )

        let companionMessages = messages.map { msg in
            CompanionChatMessage(
                id: msg.id,
                threadId: msg.threadId,
                role: msg.role,
                content: msg.content,
                tokenCount: nil,
                provider: nil,
                model: nil,
                createdAt: Int(msg.createdAt?.timeIntervalSince1970 ?? 0)
            )
        }

        return CompanionChatPayload(thread: companionThread, messages: companionMessages)
    }

    func sendChatMessage(articleId: String, content: String) async throws -> CompanionChatPayload {
        guard await currentUserId != nil else { throw SupabaseManagerError.notAuthenticated }

        let headers = userAIHeaders()

        // Call the article-chat Edge Function which saves the user message,
        // calls the AI, saves the AI response, and returns the full thread.
        let payload: CompanionChatPayload = try await client.functions.invoke(
            "article-chat",
            options: FunctionInvokeOptions(
                headers: headers,
                body: [
                    "article_id": articleId,
                    "message": content
                ]
            )
        )

        return payload
    }

    // MARK: - AI Operations

    /// Build custom headers that forward the user's own AI API key (if stored in
    /// the device Keychain) to Edge Functions. The key is sent directly to the AI
    /// provider via the Edge Function — it is never persisted server-side.
    private func userAIHeaders() -> [String: String] {
        let keychain = KeychainManager()
        if let key = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) {
            return ["x-user-api-key": key, "x-user-api-provider": "anthropic"]
        }
        if let key = keychain.get(forKey: KeychainManager.Key.openaiApiKey) {
            return ["x-user-api-key": key, "x-user-api-provider": "openai"]
        }
        return [:]
    }

    func rerunSummarize(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let headers = userAIHeaders()

        // The enrich-article edge function expects article_id, user_id, and job_type
        // Run summarize, key_points, and score in sequence
        for jobType in ["summarize", "key_points", "score"] {
            _ = try await client.functions.invoke(
                "enrich-article",
                options: FunctionInvokeOptions(
                    headers: headers,
                    body: [
                        "article_id": articleId,
                        "user_id": userId.uuidString,
                        "job_type": jobType
                    ]
                )
            )
        }
    }

    func generateKeyPoints(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let headers = userAIHeaders()

        _ = try await client.functions.invoke(
            "enrich-article",
            options: FunctionInvokeOptions(
                headers: headers,
                body: [
                    "article_id": articleId,
                    "user_id": userId.uuidString,
                    "job_type": "key_points"
                ]
            )
        )
    }

    // MARK: - News Brief

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let headers = userAIHeaders()

        struct BriefResponse: Decodable {
            let ok: Bool?
            let brief: BriefData?

            struct BriefData: Decodable {
                let id: String
                let editionType: String
                let briefText: String
                let articleIdsJson: String?
                let provider: String?
                let model: String?
                let createdAt: String?
            }
        }

        let response: BriefResponse = try await client.functions.invoke(
            "generate-news-brief",
            options: FunctionInvokeOptions(
                headers: headers,
                body: ["user_id": userId.uuidString]
            )
        )

        guard let brief = response.brief else { return nil }

        // Parse the brief_text as JSON bullets
        let bullets: [CompanionNewsBrief.Bullet]
        if let data = brief.briefText.data(using: .utf8),
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
            bullets = [CompanionNewsBrief.Bullet(text: brief.briefText, sources: [])]
        }

        return CompanionNewsBrief(
            state: "ready",
            title: "News Brief",
            editionLabel: brief.editionType.replacingOccurrences(of: "_", with: " ").capitalized,
            generatedAt: brief.createdAt.flatMap { timestampMillis($0) },
            windowHours: 12,
            scoreCutoff: 3,
            bullets: bullets,
            nextScheduledAt: nil,
            stale: false
        )
    }

    // MARK: - Device Token

    func registerDeviceToken(token: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("device_tokens")
            .upsert(DeviceTokenUpsert(userId: userId.uuidString, token: token, platform: "ios"), onConflict: "token")
            .execute()
    }

    func removeDeviceToken(token: String) async throws {
        try await client.from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }

    // MARK: - Onboarding

    func fetchOnboardingSuggestions() async throws -> OnboardingCatalog {
        // Onboarding catalog is a static asset or edge function
        // For now, return a minimal catalog; this will be expanded
        // when the edge function is deployed
        return OnboardingCatalog(categories: [
            OnboardingCategory(id: "tech", name: "Technology", icon: "desktopcomputer", feeds: [
                OnboardingFeed(url: "https://hnrss.org/frontpage", title: "Hacker News", description: "Tech news and discussion", siteUrl: "https://news.ycombinator.com"),
                OnboardingFeed(url: "https://www.theverge.com/rss/index.xml", title: "The Verge", description: "Technology, science, art, and culture", siteUrl: "https://www.theverge.com"),
                OnboardingFeed(url: "https://feeds.arstechnica.com/arstechnica/index", title: "Ars Technica", description: "Technology news and analysis", siteUrl: "https://arstechnica.com"),
                OnboardingFeed(url: "https://www.techmeme.com/feed.xml", title: "Techmeme", description: "The essential tech news of the moment", siteUrl: "https://www.techmeme.com")
            ]),
            OnboardingCategory(id: "ai", name: "AI & Machine Learning", icon: "brain", feeds: [
                OnboardingFeed(url: "https://openai.com/blog/rss.xml", title: "OpenAI Blog", description: "Research and announcements from OpenAI", siteUrl: "https://openai.com/blog"),
                OnboardingFeed(url: "https://blog.google/technology/ai/rss/", title: "Google AI Blog", description: "AI research from Google", siteUrl: "https://blog.google/technology/ai/"),
                OnboardingFeed(url: "https://machinelearningmastery.com/feed/", title: "Machine Learning Mastery", description: "Practical ML tutorials and guides", siteUrl: "https://machinelearningmastery.com")
            ]),
            OnboardingCategory(id: "science", name: "Science", icon: "atom", feeds: [
                OnboardingFeed(url: "https://www.quantamagazine.org/feed/", title: "Quanta Magazine", description: "Mathematics, physics, and biology", siteUrl: "https://www.quantamagazine.org"),
                OnboardingFeed(url: "https://www.nature.com/nature.rss", title: "Nature", description: "International scientific journal", siteUrl: "https://www.nature.com"),
                OnboardingFeed(url: "https://www.newscientist.com/feed/home/", title: "New Scientist", description: "Science and technology news", siteUrl: "https://www.newscientist.com")
            ]),
            OnboardingCategory(id: "news", name: "World News", icon: "globe", feeds: [
                OnboardingFeed(url: "https://feeds.bbci.co.uk/news/rss.xml", title: "BBC News", description: "World news from the BBC", siteUrl: "https://www.bbc.com/news"),
                OnboardingFeed(url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", title: "New York Times", description: "Top stories", siteUrl: "https://www.nytimes.com"),
                OnboardingFeed(url: "https://feeds.reuters.com/reuters/topNews", title: "Reuters", description: "International news wire", siteUrl: "https://www.reuters.com")
            ]),
            OnboardingCategory(id: "dev", name: "Software Development", icon: "chevron.left.forwardslash.chevron.right", feeds: [
                OnboardingFeed(url: "https://blog.pragmaticengineer.com/rss/", title: "The Pragmatic Engineer", description: "Software engineering and tech industry", siteUrl: "https://blog.pragmaticengineer.com"),
                OnboardingFeed(url: "https://css-tricks.com/feed/", title: "CSS-Tricks", description: "Web development tips and techniques", siteUrl: "https://css-tricks.com"),
                OnboardingFeed(url: "https://martinfowler.com/feed.atom", title: "Martin Fowler", description: "Software design and architecture", siteUrl: "https://martinfowler.com")
            ])
        ])
    }

    func bulkSubscribe(feedUrls: [String]) async throws -> Int {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        var subscribed = 0
        for url in feedUrls {
            do {
                _ = try await addFeed(url: url)
                subscribed += 1
            } catch {
                // Skip feeds that fail (e.g., duplicates)
                continue
            }
        }

        // Trigger an initial poll
        try? await triggerPull()

        return subscribed
    }
}

// MARK: - Error

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

// MARK: - Internal Row Types (for Supabase PostgREST decoding)

private struct SupabaseArticleRow: Decodable {
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

private struct SupabaseArticleDetailRow: Decodable {
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
        let tagSuggestions = articleTagSuggestions?.map { s in
            CompanionTagSuggestion(id: s.id, name: s.tagName, confidence: s.confidence.map { Double($0) })
        } ?? []

        let sources = articleSources?.map { s in
            CompanionSource(
                feedId: s.feedId,
                feedTitle: s.feeds?.title,
                siteUrl: s.feeds?.siteUrl,
                feedUrl: s.feeds?.url,
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
            summary: summary.map { CompanionArticleSummary(
                summaryText: $0.summaryText,
                provider: $0.provider,
                model: $0.model,
                createdAt: $0.createdAt.flatMap { timestampMillis($0) }
            )},
            keyPoints: keyPoints.map { CompanionKeyPoints(
                keyPointsJson: $0.keyPointsJson,
                provider: $0.provider,
                model: $0.model,
                createdAt: $0.createdAt.flatMap { timestampMillis($0) }
            )},
            score: score.map { CompanionScore(
                score: $0.score,
                label: $0.label,
                reasonText: $0.reasonText,
                evidenceJson: $0.evidenceJson,
                createdAt: $0.createdAt.flatMap { timestampMillis($0) },
                source: nil,
                status: $0.scoreStatus,
                confidence: $0.confidence.map { Double($0) },
                preferenceConfidence: $0.preferenceConfidence.map { Double($0) },
                weightedAverage: $0.weightedAverage.map { Double($0) }
            )},
            feedback: [],
            reaction: reaction.map { CompanionReaction(
                articleId: $0.articleId,
                feedId: nil,
                value: $0.value ?? 0,
                createdAt: $0.createdAt.flatMap { timestampMillis($0) },
                reasonCodes: nil
            )},
            preferredSource: sources.first,
            sources: sources,
            tags: tags,
            tagSuggestions: tagSuggestions
        )
    }
}

// MARK: - Nested row types

private struct SummaryRow: Decodable {
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

private struct KeyPointsRow: Decodable {
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

private struct ReadStateRow: Decodable {
    let isRead: Bool?
    let savedAt: String?

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case savedAt = "saved_at"
    }
}

private struct ReactionRow: Decodable {
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

private struct ScoreRow: Decodable {
    let score: Int?
    let label: String?
    let reasonText: String?
    let evidenceJson: String?
    let createdAt: String?
    let scoreStatus: String?
    let confidence: Float?
    let preferenceConfidence: Float?
    let weightedAverage: Float?

    enum CodingKeys: String, CodingKey {
        case score, label
        case reasonText = "reason_text"
        case evidenceJson = "evidence_json"
        case createdAt = "created_at"
        case scoreStatus = "score_status"
        case confidence
        case preferenceConfidence = "preference_confidence"
        case weightedAverage = "weighted_average"
    }
}

private struct SourceRow: Decodable {
    let feedId: String?
    let feeds: FeedRef?

    enum CodingKeys: String, CodingKey {
        case feedId = "feed_id"
        case feeds
    }
}

private struct FeedRef: Decodable {
    let id: String
    let title: String?
}

private struct DetailSourceRow: Decodable {
    let feedId: String?
    let feeds: DetailFeedRef?

    enum CodingKeys: String, CodingKey {
        case feedId = "feed_id"
        case feeds
    }
}

private struct DetailFeedRef: Decodable {
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

private struct ArticleTagRow: Decodable {
    let tagId: String?
    let tags: TagRef?

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tags
    }
}

private struct TagRef: Decodable {
    let id: String
    let name: String
}

private struct TagSuggestionRow: Decodable {
    let id: String
    let tagName: String
    let confidence: Float?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case confidence
    }
}

private struct SupabaseTagRow: Decodable {
    let id: String
    let name: String
}

private struct SupabaseTagWithCountRow: Decodable {
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

private struct CountRow: Decodable {
    let count: Int
}

private struct SupabaseArticleTagJoinRow: Decodable {
    let tagId: String?
    let tags: TagRef?

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tags
    }
}

private struct SupabaseFeedRow: Decodable {
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

private struct FeedDetailRow: Decodable {
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

private struct SupabaseBasicFeedRow: Decodable {
    let id: String
}

private struct SupabaseReactionRow: Decodable {
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

private struct SupabaseUserSettingRow: Decodable {
    let key: String
    let value: String
}

private struct SupabaseChatThreadRow: Decodable {
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

private struct SupabaseChatMessageRow: Decodable {
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

// MARK: - Insert/Upsert types

private struct ReadStateUpsert: Encodable {
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

private struct SaveUpsert: Encodable {
    let articleId: String
    let userId: String
    let savedAt: String?

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case savedAt = "saved_at"
    }
}

private struct ReactionUpsert: Encodable {
    let articleId: String
    let userId: String
    let value: Int

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case value
    }
}

private struct ReactionReasonInsert: Encodable {
    let articleId: String
    let userId: String
    let reasonCode: String

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
        case reasonCode = "reason_code"
    }
}

private struct TagInsert: Encodable {
    let name: String
    let nameNormalized: String
    let slug: String

    enum CodingKeys: String, CodingKey {
        case name
        case nameNormalized = "name_normalized"
        case slug
    }
}

private struct ArticleTagInsert: Encodable {
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

private struct FeedInsert: Encodable {
    let url: String
}

private struct FeedSubscriptionInsert: Encodable {
    let userId: String
    let feedId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case feedId = "feed_id"
    }
}

private struct DeviceTokenUpsert: Encodable {
    let userId: String
    let token: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case token, platform
    }
}

private struct ChatThreadInsert: Encodable {
    let articleId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case articleId = "article_id"
        case userId = "user_id"
    }
}

private struct ChatMessageInsert: Encodable {
    let threadId: String
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case role, content
    }
}

private struct UserSettingUpsert: Encodable {
    let userId: String
    let key: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case key, value
    }
}

private struct OPMLImportResponse: Decodable {
    let added: Int
}

private struct OPMLExportResponse: Decodable {
    let opml: String
}

// MARK: - Type aliases for payload compatibility

/// These type aliases let existing view code continue to use the same names.
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

// MARK: - Helpers

/// Parse an ISO 8601 timestamp string into milliseconds since epoch (matching old API format).
private func timestampMillis(_ isoString: String) -> Int? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    return nil
}

// MARK: - News Brief DTO

private struct RescoreRequest: Encodable {
    let userId: String
    let rescore: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case rescore
    }
}

private struct BriefBulletDTO: Decodable {
    let text: String
    let sourceArticleIds: [String]?

    enum CodingKeys: String, CodingKey {
        case text
        case sourceArticleIds = "source_article_ids"
    }
}

// MARK: - Read/Sort filter types (reuse existing companion names)

typealias ReadFilter = CompanionReadFilter
typealias SortOrder = CompanionSortOrder
