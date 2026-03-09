import Foundation
import SwiftData

// MARK: - Filter & Sort Types

public enum ArticleReadFilter: Sendable {
    case all, read, unread
}

public enum ArticlePresentationFilter: Sendable {
    case all
    case readyOnly
    case pendingOnly
}

public enum ArticleSort: String, Sendable, CaseIterable {
    case newest, oldest, scoreDesc, scoreAsc, unreadFirst
}

public struct ArticleFilter: Sendable {
    public var presentationFilter: ArticlePresentationFilter = .all
    public var readFilter: ArticleReadFilter = .all
    public var readingListOnly = false
    public var minScore: Int?
    public var maxScore: Int?
    public var publishedAfter: Date?
    public var feedId: String?
    public var tagIds: [String] = []
    public var searchText: String?

    public init() {}
}

// MARK: - Protocol

public protocol ArticleRepositoryProtocol: Sendable {
    func list(filter: ArticleFilter, sort: ArticleSort, limit: Int, offset: Int) async -> [Article]
    func listVisibleArticles(filter: ArticleFilter, sort: ArticleSort, limit: Int, offset: Int) async -> [Article]
    func count(filter: ArticleFilter) async -> Int
    func countVisibleArticles(filter: ArticleFilter) async -> Int
    func get(id: String) async -> Article?
    func getByHash(_ hash: String) async -> Article?
    func enrichmentSnapshot(id: String) async -> ArticleSnapshot?
    func contentFetchCandidate(id: String) async -> ArticleContentFetchCandidate?
    func listContentFetchCandidates(limit: Int, recentOnly: Bool) async -> [ArticleContentFetchCandidate]
    func insert(_ article: Article) async throws
    func insertForFeed(feedId: String, article: ParsedArticle) async throws
    func markRead(id: String, isRead: Bool) async throws
    func setReadingList(id: String, isSaved: Bool) async throws
    func react(id: String, value: Int?, reasonCodes: [String]?) async throws
    func addTag(articleId: String, tag: Tag) async throws
    func removeTag(articleId: String, tagId: String) async throws
    func updateAIFields(
        id: String,
        cardSummary: String?,
        summary: String?,
        keyPoints: [String]?,
        score: Int?,
        scoreLabel: String?,
        scoreExplanation: String?,
        summaryProvider: String?,
        summaryModel: String?
    ) async throws
    func updateFetchedContent(id: String, contentHtml: String, excerpt: String?) async throws
    func recordContentFetchAttempt(id: String) async throws
    func setPreparationState(
        id: String,
        content: ArticlePreparationStageStatus?,
        image: ArticlePreparationStageStatus?,
        enrichment: ArticlePreparationStageStatus?
    ) async throws
    func trimExcessArticlesPerFeed(maxPerFeed: Int) async throws -> Int
    func deleteOlderThan(date: Date) async throws -> Int
}

public struct ArticleFallbackImageSnapshot: Sendable {
    public let id: String
    public let title: String?
    public let canonicalUrl: String?
    public let feedTitle: String?
    public let contentText: String
    public let tags: [String]
    public let resolvedImageUrl: String?

    public init(
        id: String,
        title: String?,
        canonicalUrl: String?,
        feedTitle: String?,
        contentText: String,
        tags: [String],
        resolvedImageUrl: String?
    ) {
        self.id = id
        self.title = title
        self.canonicalUrl = canonicalUrl
        self.feedTitle = feedTitle
        self.contentText = contentText
        self.tags = tags
        self.resolvedImageUrl = resolvedImageUrl
    }
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
        var descriptor = FetchDescriptor<Article>(sortBy: sortDescriptors(for: sort))

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

        let start = min(offset, articles.count)
        let end = min(start + limit, articles.count)
        return Array(articles[start..<end])
    }

    public func listVisibleArticles(
        filter: ArticleFilter,
        sort: ArticleSort,
        limit: Int,
        offset: Int
    ) async -> [Article] {
        var visibleFilter = filter
        visibleFilter.presentationFilter = .readyOnly
        return await list(filter: visibleFilter, sort: sort, limit: limit, offset: offset)
    }

    public func count(filter: ArticleFilter) async -> Int {
        // For simple counts, fetch IDs only
        let descriptor = FetchDescriptor<Article>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return applyInMemoryFilters(all, filter: filter).count
    }

    public func countVisibleArticles(filter: ArticleFilter) async -> Int {
        var visibleFilter = filter
        visibleFilter.presentationFilter = .readyOnly
        return await count(filter: visibleFilter)
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

    public func enrichmentSnapshot(id: String) async -> ArticleSnapshot? {
        guard let article = await get(id: id) else { return nil }
        let text = article.bestAvailableContentText
        guard !text.isEmpty else { return nil }

        return ArticleSnapshot(
            id: article.id,
            title: article.title,
            contentText: text,
            canonicalUrl: article.canonicalUrl,
            feedTitle: article.feed?.title
        )
    }

    public func contentFetchCandidate(id: String) async -> ArticleContentFetchCandidate? {
        guard let article = await get(id: id) else { return nil }
        return articleContentFetchCandidate(from: article)
    }

    public func fallbackImageSnapshot(id: String) async -> ArticleFallbackImageSnapshot? {
        guard let article = await get(id: id) else { return nil }

        let text = article.bestAvailableContentText
        let tags = (article.tags ?? [])
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return ArticleFallbackImageSnapshot(
            id: article.id,
            title: article.title,
            canonicalUrl: article.canonicalUrl,
            feedTitle: article.feed?.title,
            contentText: text,
            tags: tags,
            resolvedImageUrl: article.resolvedImageUrl
        )
    }

    public func listContentFetchCandidates(limit: Int = 10, recentOnly: Bool = true) async -> [ArticleContentFetchCandidate] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse), SortDescriptor(\.fetchedAt, order: .reverse)]
        )

        guard let articles = try? modelContext.fetch(descriptor) else {
            return []
        }

        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast

        return articles
            .filter { article in
                !recentOnly || article.retentionReferenceDate >= recentCutoff
            }
            .compactMap { article in
                articleContentFetchCandidate(from: article)
            }
            .prefix(limit)
            .map { $0 }
    }

    public func insert(_ article: Article) async throws {
        if article.contentPreparationStatusRaw == nil {
            article.contentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        }
        if article.imagePreparationStatusRaw == nil {
            article.imagePreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        }
        if article.enrichmentPreparationStatusRaw == nil {
            article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        }
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
        newArticle.contentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        newArticle.imagePreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        newArticle.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        newArticle.presentationReadyAt = nil

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

    public func setReadingList(id: String, isSaved: Bool) async throws {
        guard let article = await get(id: id) else { return }
        if isSaved {
            article.addToReadingList()
        } else {
            article.removeFromReadingList()
        }
        try modelContext.save()
    }

    public func react(id: String, value: Int?, reasonCodes: [String]?) async throws {
        guard let article = await get(id: id) else { return }
        article.setReaction(value: value, reasonCodes: reasonCodes)
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
        cardSummary: String?,
        summary: String?,
        keyPoints: [String]?,
        score: Int?,
        scoreLabel: String?,
        scoreExplanation: String?,
        summaryProvider: String?,
        summaryModel: String?
    ) async throws {
        guard let article = await get(id: id) else { return }
        if let cardSummary { article.cardSummaryText = cardSummary }
        if let summary { article.summaryText = summary }
        if let keyPoints {
            article.keyPointsJson = String(data: try JSONEncoder().encode(keyPoints), encoding: .utf8)
        }
        if let score { article.score = score }
        if let scoreLabel { article.scoreLabel = scoreLabel }
        if let scoreExplanation { article.scoreExplanation = scoreExplanation }
        if let summaryProvider { article.summaryProvider = summaryProvider }
        if let summaryModel { article.summaryModel = summaryModel }
        article.aiProcessedAt = Date()
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
    }

    public func updateFetchedContent(id: String, contentHtml: String, excerpt: String?) async throws {
        guard let article = await get(id: id) else { return }

        article.contentHtml = contentHtml
        if (article.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let excerpt,
           !excerpt.isEmpty {
            article.excerpt = excerpt
        }

        let now = Date()
        article.contentFetchAttemptedAt = now
        article.contentFetchedAt = now
        article.contentPreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue

        // Recompute downstream outputs from the fuller article body.
        article.summaryText = nil
        article.cardSummaryText = nil
        article.summaryProvider = nil
        article.summaryModel = nil
        article.keyPointsJson = nil
        article.aiProcessedAt = nil
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue

        article.score = nil
        article.scoreLabel = nil
        article.scoreConfidence = nil
        article.scorePreferenceConfidence = nil
        article.scoreWeightedAverage = nil
        article.scoreExplanation = nil
        article.scoreStatus = nil
        article.signalScoresJson = nil

        article.scoreAssistExplanation = nil
        article.scoreAssistProvider = nil
        article.scoreAssistModel = nil
        article.scoreAssistAdjustment = nil
        article.scoreAssistGeneratedAt = nil

        article.personalizationVersion = 0

        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
    }

    public func recordContentFetchAttempt(id: String) async throws {
        guard let article = await get(id: id) else { return }
        article.contentFetchAttemptedAt = Date()
        try modelContext.save()
    }

    public func updateFallbackImage(
        id: String,
        url: String,
        provider: String,
        themeKey: String
    ) async throws {
        guard let article = await get(id: id) else { return }
        guard article.imageUrl == nil, article.ogImageUrl == nil else { return }

        article.fallbackImageUrl = url
        article.fallbackImageProvider = provider
        article.fallbackImageTheme = themeKey
        article.fallbackImageGeneratedAt = Date()
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
    }

    /// Returns snapshots of articles that haven't been AI-processed yet and have content.
    ///
    /// Used by `AIEnrichmentService` to find articles needing scoring/summarization.
    /// Results are `Sendable` structs safe to pass across actor boundaries.
    public func listUnprocessedSnapshots(limit: Int = 10) async -> [ArticleSnapshot] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )

        guard let articles = try? modelContext.fetch(descriptor) else { return [] }

        return articles.compactMap { article in
            let needsAI = article.aiProcessedAt == nil ||
                (article.cardSummaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
                (article.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
                article.keyPoints.isEmpty
            guard needsAI else { return nil }

            let text = article.bestAvailableContentText
            guard !text.isEmpty else { return nil }

            return ArticleSnapshot(
                id: article.id,
                title: article.title,
                contentText: text,
                canonicalUrl: article.canonicalUrl,
                feedTitle: article.feed?.title
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    public func updateOGImageUrl(id: String, ogImageUrl: String) async throws {
        guard let article = await get(id: id) else { return }
        article.ogImageUrl = ogImageUrl
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
    }

    public func setPreparationState(
        id: String,
        content: ArticlePreparationStageStatus? = nil,
        image: ArticlePreparationStageStatus? = nil,
        enrichment: ArticlePreparationStageStatus? = nil
    ) async throws {
        guard let article = await get(id: id) else { return }

        if let content {
            article.contentPreparationStatusRaw = content.rawValue
        }
        if let image {
            article.imagePreparationStatusRaw = image.rawValue
        }
        if let enrichment {
            article.enrichmentPreparationStatusRaw = enrichment.rawValue
        }

        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
    }

    public func trimExcessArticlesPerFeed(maxPerFeed: Int) async throws -> Int {
        let limit = max(maxPerFeed, 1)
        let descriptor = FetchDescriptor<Article>()
        let allArticles = try modelContext.fetch(descriptor)

        let groupedByFeed = Dictionary(grouping: allArticles) { article in
            article.feed?.id
        }

        var deleted = 0

        for (feedID, articles) in groupedByFeed {
            guard feedID != nil else { continue }

            let sorted = articles.sorted { lhs, rhs in
                if lhs.retentionReferenceDate != rhs.retentionReferenceDate {
                    return lhs.retentionReferenceDate > rhs.retentionReferenceDate
                }
                return lhs.fetchedAt > rhs.fetchedAt
            }

            var keptUnsaved = 0

            for article in sorted {
                if article.isInReadingList {
                    continue
                }

                if keptUnsaved < limit {
                    keptUnsaved += 1
                    continue
                }

                modelContext.delete(article)
                deleted += 1
            }
        }

        if deleted > 0 {
            try modelContext.save()
        }

        return deleted
    }

    public func deleteOlderThan(date: Date) async throws -> Int {
        let descriptor = FetchDescriptor<Article>()
        let old = try modelContext.fetch(descriptor).filter { article in
            !article.isInReadingList && article.retentionReferenceDate < date
        }

        guard !old.isEmpty else {
            return 0
        }

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

    private func articleContentFetchCandidate(from article: Article) -> ArticleContentFetchCandidate? {
        guard article.needsContentFetch() else {
            return nil
        }

        guard let canonicalUrl = article.canonicalUrl else {
            return nil
        }

        return ArticleContentFetchCandidate(
            id: article.id,
            canonicalUrl: canonicalUrl,
            title: article.title,
            currentTextLength: article.bestAvailableContentLength,
            sortDate: article.publishedAt ?? article.fetchedAt
        )
    }

    private func applyInMemoryFilters(_ articles: [Article], filter: ArticleFilter) -> [Article] {
        var result = articles

        switch filter.presentationFilter {
        case .all:
            break
        case .readyOnly:
            result = result.filter(\.isPresentationReady)
        case .pendingOnly:
            result = result.filter(\.isPreparationPending)
        }

        switch filter.readFilter {
        case .all: break
        case .read: result = result.filter { $0.isRead }
        case .unread: result = result.filter(\.isUnreadQueueCandidate)
        }

        if filter.readingListOnly {
            result = result.filter(\.isInReadingList)
        }

        if let min = filter.minScore {
            result = result.filter { ($0.score ?? 0) >= min }
        }
        if let max = filter.maxScore {
            result = result.filter { ($0.score ?? 0) <= max }
        }

        if let publishedAfter = filter.publishedAfter {
            result = result.filter {
                ($0.publishedAt ?? $0.fetchedAt) >= publishedAfter
            }
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
                article.cardSummaryText?.localizedCaseInsensitiveContains(search) == true ||
                article.summaryText?.localizedCaseInsensitiveContains(search) == true ||
                article.author?.localizedCaseInsensitiveContains(search) == true
            }
        }

        return result
    }

    private func applyPresentationReadyIfNeeded(to article: Article) {
        guard article.presentationReadyAt == nil else {
            return
        }

        if article.hasAttemptedPresentationPreparation {
            article.presentationReadyAt = Date()
        }
    }
}
