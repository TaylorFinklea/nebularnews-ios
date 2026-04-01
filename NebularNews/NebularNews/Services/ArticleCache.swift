import Foundation
import SwiftData
import os

/// Bridges SwiftData local cache with Supabase remote data.
///
/// Pattern: show cached data instantly, fetch from Supabase in background,
/// update cache, UI refreshes via SwiftData observation.
@MainActor
@Observable
final class ArticleCache {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.nebularnews", category: "ArticleCache")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Articles

    /// Return cached articles instantly (no network).
    func getCachedArticles(
        readFilter: CompanionReadFilter = .all,
        minScore: Int? = nil,
        sortOrder: CompanionSortOrder = .newest,
        query: String = "",
        limit: Int = 40
    ) -> [CachedArticle] {
        var descriptor = FetchDescriptor<CachedArticle>()
        descriptor.fetchLimit = limit

        // Sort by cachedAt (non-optional Date that tracks fetch order)
        switch sortOrder {
        case .newest, .score, .unreadFirst:
            descriptor.sortBy = [SortDescriptor(\CachedArticle.cachedAt, order: .reverse)]
        case .oldest:
            descriptor.sortBy = [SortDescriptor(\CachedArticle.cachedAt, order: .forward)]
        }

        // Build predicate
        // Build predicate based on active filters.
        // SwiftData predicates must be constructed statically, so we branch
        // on the filter combination rather than composing at runtime.
        let hasSearch = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let searchTerm = query.lowercased()
        let scoreThreshold = minScore ?? 0
        let filteringScore = minScore != nil

        switch (readFilter, filteringScore, hasSearch) {
        case (.unread, false, false):
            descriptor.predicate = #Predicate<CachedArticle> { $0.isRead == false }
        case (.read, false, false):
            descriptor.predicate = #Predicate<CachedArticle> { $0.isRead == true }
        case (.unread, true, false):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == false && (article.score ?? 0) >= scoreThreshold
            }
        case (.read, true, false):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == true && (article.score ?? 0) >= scoreThreshold
            }
        case (.all, true, false):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                (article.score ?? 0) >= scoreThreshold
            }
        case (.unread, false, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == false
                && ((article.title ?? "").localizedStandardContains(searchTerm)
                    || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                    || (article.sourceName ?? "").localizedStandardContains(searchTerm))
            }
        case (.read, false, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == true
                && ((article.title ?? "").localizedStandardContains(searchTerm)
                    || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                    || (article.sourceName ?? "").localizedStandardContains(searchTerm))
            }
        case (.all, false, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                (article.title ?? "").localizedStandardContains(searchTerm)
                || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                || (article.sourceName ?? "").localizedStandardContains(searchTerm)
            }
        case (.unread, true, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == false
                && (article.score ?? 0) >= scoreThreshold
                && ((article.title ?? "").localizedStandardContains(searchTerm)
                    || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                    || (article.sourceName ?? "").localizedStandardContains(searchTerm))
            }
        case (.read, true, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                article.isRead == true
                && (article.score ?? 0) >= scoreThreshold
                && ((article.title ?? "").localizedStandardContains(searchTerm)
                    || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                    || (article.sourceName ?? "").localizedStandardContains(searchTerm))
            }
        case (.all, true, true):
            descriptor.predicate = #Predicate<CachedArticle> { article in
                (article.score ?? 0) >= scoreThreshold
                && ((article.title ?? "").localizedStandardContains(searchTerm)
                    || (article.excerpt ?? "").localizedStandardContains(searchTerm)
                    || (article.sourceName ?? "").localizedStandardContains(searchTerm))
            }
        case (.all, false, false):
            break // No predicate needed
        }

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch cached articles: \(error, privacy: .public)")
            return []
        }
    }

    /// Sync articles from Supabase into the SwiftData cache.
    /// Returns the synced articles converted to `CompanionArticleListItem` for view compatibility.
    func syncArticles(
        from supabase: SupabaseManager,
        query: String = "",
        read: CompanionReadFilter = .all,
        minScore: Int? = nil,
        sort: CompanionSortOrder = .newest,
        limit: Int = 40,
        offset: Int = 0,
        sinceDays: Int? = nil,
        tag: String? = nil,
        saved: Bool = false
    ) async throws -> CompanionArticlesPayload {
        let payload = try await supabase.fetchArticles(
            query: query,
            offset: offset,
            limit: limit,
            read: read,
            minScore: minScore,
            sort: sort,
            sinceDays: sinceDays,
            tag: tag,
            saved: saved
        )

        // Upsert each article into the cache
        for item in payload.articles {
            upsertArticle(from: item)
        }

        save()
        return payload
    }

    /// Update a single cached article's user state (after read/save/reaction actions).
    func updateArticle(id: String, isRead: Bool? = nil, saved: Bool? = nil, reactionValue: Int? = nil) {
        guard let cached = findCachedArticle(id: id) else { return }

        if let isRead {
            cached.isRead = isRead
        }
        if let saved {
            cached.savedAt = saved ? Date() : nil
        }
        if let reactionValue {
            cached.reactionValue = reactionValue
        }
        cached.lastSyncedAt = Date()
        save()
    }

    /// Upsert a single article from a CompanionArticleListItem (e.g. from Today payload).
    func updateArticleFromListItem(_ item: CompanionArticleListItem) {
        upsertArticle(from: item)
        save()
    }

    // MARK: - Feeds

    /// Sync feeds from Supabase into SwiftData cache.
    func syncFeeds(from supabase: SupabaseManager) async throws -> [CachedFeed] {
        let feeds = try await supabase.fetchFeeds()

        for feed in feeds {
            upsertFeed(from: feed)
        }

        save()
        return getCachedFeeds()
    }

    /// Return cached feeds instantly.
    func getCachedFeeds() -> [CachedFeed] {
        var descriptor = FetchDescriptor<CachedFeed>()
        descriptor.sortBy = [SortDescriptor(\.title)]
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch cached feeds: \(error, privacy: .public)")
            return []
        }
    }

    // MARK: - Cache management

    /// Remove articles cached more than `days` ago that aren't saved.
    func clearOlderThan(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var descriptor = FetchDescriptor<CachedArticle>(
            predicate: #Predicate<CachedArticle> { article in
                article.cachedAt < cutoff && article.savedAt == nil
            }
        )
        descriptor.fetchLimit = 500

        do {
            let stale = try modelContext.fetch(descriptor)
            for article in stale {
                modelContext.delete(article)
            }
            save()
            if !stale.isEmpty {
                logger.info("Evicted \(stale.count) stale cached articles")
            }
        } catch {
            logger.error("Failed to evict stale articles: \(error, privacy: .public)")
        }
    }

    /// Number of cached articles.
    var cacheSize: Int {
        let descriptor = FetchDescriptor<CachedArticle>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Conversion helpers

    /// Convert a CachedArticle to CompanionArticleListItem for existing views.
    static func toListItem(_ cached: CachedArticle) -> CompanionArticleListItem {
        let publishedAtMillis: Int? = cached.publishedAt.map { Int($0.timeIntervalSince1970 * 1000) }
        let fetchedAtMillis: Int? = cached.fetchedAt.map { Int($0.timeIntervalSince1970 * 1000) }

        var tags: [CompanionTag]?
        if let json = cached.tagsJson, let data = json.data(using: .utf8) {
            tags = try? JSONDecoder().decode([CompanionTag].self, from: data)
        }

        return CompanionArticleListItem(
            id: cached.id,
            canonicalUrl: cached.canonicalUrl,
            imageUrl: cached.imageUrl,
            title: cached.title,
            author: cached.author,
            publishedAt: publishedAtMillis,
            fetchedAt: fetchedAtMillis,
            excerpt: cached.excerpt,
            summaryText: cached.summaryText,
            isRead: cached.isRead ? 1 : 0,
            reactionValue: cached.reactionValue,
            reactionReasonCodes: nil,
            score: cached.score,
            scoreLabel: cached.scoreLabel,
            scoreStatus: cached.scoreStatus,
            scoreConfidence: cached.scoreConfidence,
            sourceName: cached.sourceName,
            sourceFeedId: cached.sourceFeedId,
            tags: tags
        )
    }

    /// Convert an array of CachedArticle to CompanionArticleListItem array.
    static func toListItems(_ cached: [CachedArticle]) -> [CompanionArticleListItem] {
        cached.map { toListItem($0) }
    }

    // MARK: - Private

    private func findCachedArticle(id: String) -> CachedArticle? {
        let articleId = id
        var descriptor = FetchDescriptor<CachedArticle>(
            predicate: #Predicate<CachedArticle> { $0.id == articleId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertArticle(from item: CompanionArticleListItem) {
        let cached = findCachedArticle(id: item.id) ?? {
            let new = CachedArticle(id: item.id)
            modelContext.insert(new)
            return new
        }()

        cached.canonicalUrl = item.canonicalUrl
        cached.title = item.title
        cached.author = item.author
        cached.imageUrl = item.imageUrl
        cached.excerpt = item.excerpt
        cached.summaryText = item.summaryText
        cached.isRead = (item.isRead ?? 0) == 1
        cached.reactionValue = item.reactionValue
        cached.score = item.score
        cached.scoreLabel = item.scoreLabel
        cached.scoreStatus = item.scoreStatus
        cached.scoreConfidence = item.scoreConfidence
        cached.sourceName = item.sourceName
        cached.sourceFeedId = item.sourceFeedId
        cached.lastSyncedAt = Date()

        // Convert epoch millis to Date
        if let millis = item.publishedAt {
            cached.publishedAt = Date(timeIntervalSince1970: Double(millis) / 1000)
        }
        if let millis = item.fetchedAt {
            cached.fetchedAt = Date(timeIntervalSince1970: Double(millis) / 1000)
        }

        // Tags as JSON
        if let tags = item.tags {
            cached.tagsJson = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? nil
        }
    }

    private func upsertFeed(from feed: CompanionFeed) {
        let feedId = feed.id
        var descriptor = FetchDescriptor<CachedFeed>(
            predicate: #Predicate<CachedFeed> { $0.id == feedId }
        )
        descriptor.fetchLimit = 1
        let cached = (try? modelContext.fetch(descriptor).first) ?? {
            let new = CachedFeed(id: feed.id)
            modelContext.insert(new)
            return new
        }()

        cached.url = feed.url
        cached.title = feed.title
        cached.siteUrl = feed.siteUrl
        cached.articleCount = feed.articleCount ?? 0
        cached.errorCount = feed.errorCount ?? 0
        cached.paused = feed.paused ?? false
        cached.maxArticlesPerDay = feed.maxArticlesPerDay
        cached.minScore = feed.minScore
        cached.cachedAt = Date()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save model context: \(error, privacy: .public)")
        }
    }
}
