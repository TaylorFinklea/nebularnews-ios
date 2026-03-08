import Foundation
import SwiftData

// MARK: - Filter & Sort Types

public enum ArticleReadFilter: Sendable {
    case all, read, unread
}

public enum ArticleSort: String, Sendable, CaseIterable {
    case newest, oldest, scoreDesc, scoreAsc, unreadFirst
}

public struct ArticleFilter: Sendable {
    public var readFilter: ArticleReadFilter = .all
    public var minScore: Int?
    public var maxScore: Int?
    public var feedId: String?
    public var tagIds: [String] = []
    public var searchText: String?

    public init() {}
}

// MARK: - Protocol

public protocol ArticleRepositoryProtocol: Sendable {
    func list(filter: ArticleFilter, sort: ArticleSort, limit: Int, offset: Int) async -> [Article]
    func count(filter: ArticleFilter) async -> Int
    func get(id: String) async -> Article?
    func getByHash(_ hash: String) async -> Article?
    func insert(_ article: Article) async throws
    func insertForFeed(feedId: String, article: ParsedArticle) async throws
    func markRead(id: String, isRead: Bool) async throws
    func react(id: String, value: Int?, reasonCodes: [String]?) async throws
    func addTag(articleId: String, tag: Tag) async throws
    func removeTag(articleId: String, tagId: String) async throws
    func updateAIFields(id: String, summary: String?, keyPoints: [String]?, score: Int?, scoreLabel: String?, scoreExplanation: String?) async throws
    func deleteOlderThan(date: Date) async throws -> Int
}

// MARK: - Local Implementation

@ModelActor
public actor LocalArticleRepository: ArticleRepositoryProtocol {

    public func list(
        filter: ArticleFilter,
        sort: ArticleSort,
        limit: Int,
        offset: Int
    ) async -> [Article] {
        var descriptor = FetchDescriptor<Article>(
            sortBy: sortDescriptors(for: sort)
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        // SwiftData #Predicate is limited — we apply simple predicates at the
        // query level and do in-memory filtering for complex conditions.
        if let feedId = filter.feedId {
            descriptor.predicate = #Predicate<Article> { article in
                article.feed?.id == feedId
            }
        }

        guard var articles = try? modelContext.fetch(descriptor) else {
            return []
        }

        // In-memory filters for conditions #Predicate can't express easily
        articles = applyInMemoryFilters(articles, filter: filter)
        if sort == .unreadFirst {
            articles.sort { lhs, rhs in
                if lhs.isUnreadQueueCandidate != rhs.isUnreadQueueCandidate {
                    return lhs.isUnreadQueueCandidate
                }
                return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
        }

        return articles
    }

    public func count(filter: ArticleFilter) async -> Int {
        // For simple counts, fetch IDs only
        let descriptor = FetchDescriptor<Article>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return applyInMemoryFilters(all, filter: filter).count
    }

    public func get(id: String) async -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func getByHash(_ hash: String) async -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func insert(_ article: Article) async throws {
        modelContext.insert(article)
        try modelContext.save()
    }

    public func insertForFeed(feedId: String, article: ParsedArticle) async throws {
        // Fetch the Feed from THIS actor's ModelContext so both objects share the same context
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.id == feedId }
        )
        descriptor.fetchLimit = 1
        guard let feed = try? modelContext.fetch(descriptor).first else { return }

        let newArticle = Article(canonicalUrl: article.url, title: article.title)
        newArticle.author = article.author
        newArticle.publishedAt = article.publishedAt
        newArticle.contentHtml = article.contentHtml
        newArticle.excerpt = article.excerpt
        newArticle.imageUrl = article.imageUrl
        newArticle.contentHash = article.contentHash
        newArticle.feed = feed

        modelContext.insert(newArticle)
        try modelContext.save()
    }

    public func markRead(id: String, isRead: Bool) async throws {
        guard let article = await get(id: id) else { return }
        if isRead {
            article.markRead()
        } else {
            article.markUnread()
        }
        try modelContext.save()
    }

    public func react(id: String, value: Int?, reasonCodes: [String]?) async throws {
        guard let article = await get(id: id) else { return }
        article.reactionValue = value
        article.reactionReasonCodes = reasonCodes?.joined(separator: ",")
        try modelContext.save()
    }

    public func addTag(articleId: String, tag: Tag) async throws {
        guard let article = await get(id: articleId) else { return }
        if article.tags == nil { article.tags = [] }
        if !(article.tags?.contains(where: { $0.id == tag.id }) ?? false) {
            article.tags?.append(tag)
            try modelContext.save()
        }
    }

    public func removeTag(articleId: String, tagId: String) async throws {
        guard let article = await get(id: articleId) else { return }
        article.tags?.removeAll(where: { $0.id == tagId })
        try modelContext.save()
    }

    public func updateAIFields(
        id: String,
        summary: String?,
        keyPoints: [String]?,
        score: Int?,
        scoreLabel: String?,
        scoreExplanation: String?
    ) async throws {
        guard let article = await get(id: id) else { return }
        if let summary { article.summaryText = summary }
        if let keyPoints {
            article.keyPointsJson = String(data: try JSONEncoder().encode(keyPoints), encoding: .utf8)
        }
        if let score { article.score = score }
        if let scoreLabel { article.scoreLabel = scoreLabel }
        if let scoreExplanation { article.scoreExplanation = scoreExplanation }
        article.aiProcessedAt = Date()
        try modelContext.save()
    }

    /// Returns snapshots of articles that haven't been AI-processed yet and have content.
    ///
    /// Used by `AIEnrichmentService` to find articles needing scoring/summarization.
    /// Results are `Sendable` structs safe to pass across actor boundaries.
    public func listUnprocessedSnapshots(limit: Int = 10) async -> [ArticleSnapshot] {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.aiProcessedAt == nil },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        guard let articles = try? modelContext.fetch(descriptor) else { return [] }

        return articles.compactMap { article in
            // Need content to send to the LLM
            let html = article.contentHtml ?? article.excerpt ?? ""
            let text = html.strippedHTML
            guard !text.isEmpty else { return nil }

            return ArticleSnapshot(
                id: article.id,
                title: article.title,
                contentText: text,
                canonicalUrl: article.canonicalUrl,
                feedTitle: article.feed?.title
            )
        }
    }

    public func updateOGImageUrl(id: String, ogImageUrl: String) async throws {
        guard let article = await get(id: id) else { return }
        article.ogImageUrl = ogImageUrl
        try modelContext.save()
    }

    public func deleteOlderThan(date: Date) async throws -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.fetchedAt < date }
        )
        let old = (try? modelContext.fetch(descriptor)) ?? []
        for article in old {
            modelContext.delete(article)
        }
        try modelContext.save()
        return old.count
    }

    // MARK: - Private

    private func sortDescriptors(for sort: ArticleSort) -> [SortDescriptor<Article>] {
        switch sort {
        case .newest:
            return [SortDescriptor(\.publishedAt, order: .reverse)]
        case .oldest:
            return [SortDescriptor(\.publishedAt, order: .forward)]
        case .scoreDesc:
            return [SortDescriptor(\.score, order: .reverse)]
        case .scoreAsc:
            return [SortDescriptor(\.score, order: .forward)]
        case .unreadFirst:
            return [SortDescriptor(\.publishedAt, order: .reverse)]
        }
    }

    private func applyInMemoryFilters(_ articles: [Article], filter: ArticleFilter) -> [Article] {
        var result = articles

        switch filter.readFilter {
        case .all: break
        case .read: result = result.filter { $0.isRead }
        case .unread: result = result.filter(\.isUnreadQueueCandidate)
        }

        if let min = filter.minScore {
            result = result.filter { ($0.score ?? 0) >= min }
        }
        if let max = filter.maxScore {
            result = result.filter { ($0.score ?? 0) <= max }
        }

        if !filter.tagIds.isEmpty {
            result = result.filter { article in
                let articleTagIds = Set(article.tags?.map(\.id) ?? [])
                return !articleTagIds.isDisjoint(with: filter.tagIds)
            }
        }

        if let search = filter.searchText, !search.isEmpty {
            result = result.filter { article in
                article.title?.localizedCaseInsensitiveContains(search) == true ||
                article.excerpt?.localizedCaseInsensitiveContains(search) == true ||
                article.summaryText?.localizedCaseInsensitiveContains(search) == true ||
                article.author?.localizedCaseInsensitiveContains(search) == true
            }
        }

        return result
    }
}
