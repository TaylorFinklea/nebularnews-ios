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

public struct ArticleListCursor: Codable, Hashable, Sendable {
    public let sortDate: Date
    public let articleID: String

    public init(sortDate: Date, articleID: String) {
        self.sortDate = sortDate
        self.articleID = articleID
    }
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
    func listFeedPage(filter: ArticleFilter, cursor: ArticleListCursor?, limit: Int) async -> [Article]
    func countFeed(filter: ArticleFilter) async -> Int
    func fetchTodaySnapshot() async -> TodaySnapshot
    func rebuildTodaySnapshot() async
    func fetchReadingListPage(filter: ArticleFilter, cursor: ArticleListCursor?, limit: Int) async -> [Article]
    func listArticles(ids: [String]) async -> [Article]
    func get(id: String) async -> Article?
    func getByHash(_ hash: String) async -> Article?
    func enrichmentSnapshot(id: String) async -> ArticleSnapshot?
    func contentFetchCandidate(id: String) async -> ArticleContentFetchCandidate?
    func listContentFetchCandidates(limit: Int, recentOnly: Bool) async -> [ArticleContentFetchCandidate]
    func pendingVisibleArticleCount() async -> Int
    func backfillMissingProcessingJobsForInvisibleArticles(limit: Int) async throws -> Int
    func backfillMissingImageJobsForVisibleArticles(limit: Int) async throws -> Int
    func enqueueMissingProcessingJobs(for articleID: String) async throws
    func claimProcessingJobs(limit: Int, allowLowPriority: Bool) async -> [String]
    func processingJob(articleID: String, stage: ArticleProcessingStage) async -> ArticleProcessingJob?
    func completeProcessingJob(articleID: String, stage: ArticleProcessingStage, status: ArticleProcessingJobStatus, inputRevision: Int, error: String?) async throws
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
    public let fallbackImageProvider: String?

    public init(
        id: String,
        title: String?,
        canonicalUrl: String?,
        feedTitle: String?,
        contentText: String,
        tags: [String],
        resolvedImageUrl: String?,
        fallbackImageProvider: String?
    ) {
        self.id = id
        self.title = title
        self.canonicalUrl = canonicalUrl
        self.feedTitle = feedTitle
        self.contentText = contentText
        self.tags = tags
        self.resolvedImageUrl = resolvedImageUrl
        self.fallbackImageProvider = fallbackImageProvider
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
        let searchText = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsInMemoryFiltering =
            filter.readFilter != .all ||
            filter.minScore != nil ||
            filter.maxScore != nil ||
            filter.publishedAfter != nil ||
            filter.feedId != nil ||
            !filter.tagIds.isEmpty ||
            !((searchText?.isEmpty) ?? true)

        let baseDescriptor = baseCountDescriptor(
            presentationFilter: filter.presentationFilter,
            requireReadingList: filter.readingListOnly
        )

        if !needsInMemoryFiltering,
           let count = try? modelContext.fetchCount(baseDescriptor) {
            return count
        }

        let all = (try? modelContext.fetch(baseDescriptor)) ?? []
        return applyInMemoryFilters(all, filter: filter).count
    }

    public func countVisibleArticles(filter: ArticleFilter) async -> Int {
        var visibleFilter = filter
        visibleFilter.presentationFilter = .readyOnly
        return await count(filter: visibleFilter)
    }

    public func listFeedPage(
        filter: ArticleFilter,
        cursor: ArticleListCursor?,
        limit: Int
    ) async -> [Article] {
        var feedFilter = filter
        feedFilter.presentationFilter = .readyOnly
        return await pagedArticles(
            filter: feedFilter,
            cursor: cursor,
            limit: limit,
            requireReadingList: false
        )
    }

    public func countFeed(filter: ArticleFilter) async -> Int {
        var feedFilter = filter
        feedFilter.presentationFilter = .readyOnly
        return await count(filter: feedFilter)
    }

    public func fetchTodaySnapshot() async -> TodaySnapshot {
        var descriptor = FetchDescriptor<TodaySnapshot>(
            predicate: #Predicate<TodaySnapshot> { $0.id == "singleton" }
        )
        descriptor.fetchLimit = 1
        if let snapshot = try? modelContext.fetch(descriptor).first {
            return snapshot
        }

        let snapshot = TodaySnapshot()
        modelContext.insert(snapshot)
        try? modelContext.save()
        return snapshot
    }

    public func rebuildTodaySnapshot() async {
        let snapshot = await fetchTodaySnapshot()
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)

        snapshot.generatedAt = now
        snapshot.unreadCount = unreadVisibleCount()
        snapshot.newTodayCount = unreadVisibleCount(publishedAfter: dayAgo)
        snapshot.highFitCount = highFitUnreadVisibleCount()
        snapshot.readyArticleCount = readyVisibleCount()

        let topArticles = topVisibleUnreadArticles(limit: 10)
        snapshot.heroArticleID = topArticles.first?.id
        snapshot.updateUpNextArticleIDs(Array(topArticles.dropFirst()).map(\.id))
        snapshot.sourceWatermark = topArticles.first?.querySortDate ?? now

        try? modelContext.save()
        ArticleChangeBus.postTodaySnapshotChanged()
    }

    public func fetchReadingListPage(
        filter: ArticleFilter,
        cursor: ArticleListCursor?,
        limit: Int
    ) async -> [Article] {
        var readingListFilter = filter
        readingListFilter.readingListOnly = true
        readingListFilter.presentationFilter = .readyOnly
        return await pagedArticles(
            filter: readingListFilter,
            cursor: cursor,
            limit: limit,
            requireReadingList: true
        )
    }

    public func listArticles(ids: [String]) async -> [Article] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func pendingVisibleArticleCount() async -> Int {
        let descriptor = FetchDescriptor<ArticleProcessingJob>()
        let jobs = ((try? modelContext.fetch(descriptor)) ?? []).filter { job in
            job.stage == .scoreAndTag && (job.status == .queued || job.status == .running)
        }

        var count = 0
        for job in jobs {
            guard let article = await get(id: job.articleID),
                  article.queryIsVisible == false else {
                continue
            }
            count += 1
        }

        return count
    }

    public func backfillMissingProcessingJobsForInvisibleArticles(limit: Int) async throws -> Int {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.queryIsVisible == false },
            sortBy: [SortDescriptor(\.querySortDate, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 0)

        let hiddenArticles = try modelContext.fetch(descriptor)
        var touched = 0

        for article in hiddenArticles {
            let previousQueuedJob = try existingProcessingJob(
                articleID: article.id,
                stage: .scoreAndTag
            )

            try await enqueueMissingProcessingJobs(for: article.id)

            let refreshedJob = try existingProcessingJob(
                articleID: article.id,
                stage: .scoreAndTag
            )

            if previousQueuedJob?.status != .queued,
               refreshedJob?.status == .queued {
                touched += 1
            }
        }

        return touched
    }

    public func backfillMissingImageJobsForVisibleArticles(limit: Int) async throws -> Int {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> {
                $0.queryIsVisible == true &&
                $0.imageUrl == nil &&
                $0.ogImageUrl == nil &&
                $0.imagePreparedRevision < currentImagePreparationRevision
            },
            sortBy: [SortDescriptor(\.querySortDate, order: .reverse)]
        )
        descriptor.fetchLimit = max(limit, 0)

        let visibleArticles = try modelContext.fetch(descriptor)
        var touched = 0

        for article in visibleArticles {
            let previousQueuedJob = try existingProcessingJob(
                articleID: article.id,
                stage: .resolveImage
            )

            try ensureProcessingJobIfNeeded(
                articleID: article.id,
                stage: .resolveImage,
                priority: 150,
                inputRevision: currentImagePreparationRevision,
                shouldQueue: true
            )

            let refreshedJob = try existingProcessingJob(
                articleID: article.id,
                stage: .resolveImage
            )

            if previousQueuedJob?.status != .queued,
               refreshedJob?.status == .queued {
                touched += 1
            }
        }

        try modelContext.save()
        return touched
    }

    public func enqueueMissingProcessingJobs(for articleID: String) async throws {
        guard let article = await get(id: articleID) else { return }

        try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .scoreAndTag,
            priority: 300,
            inputRevision: max(article.contentRevision, currentPersonalizationVersion),
            shouldQueue: article.scorePreparedRevision < max(article.contentRevision, currentPersonalizationVersion) ||
                article.queryIsVisible == false
        )

        try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .fetchContent,
            priority: 200,
            inputRevision: article.contentRevision,
            shouldQueue: article.contentFetchAttemptedAt == nil && article.needsContentFetch()
        )

        try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .generateSummary,
            priority: 100,
            inputRevision: article.contentRevision,
            shouldQueue: article.summaryPreparedRevision < article.contentRevision
        )

        try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .resolveImage,
            priority: 150,
            inputRevision: currentImagePreparationRevision,
            shouldQueue: article.imageUrl == nil &&
                article.ogImageUrl == nil &&
                article.imagePreparedRevision < currentImagePreparationRevision
        )

        try modelContext.save()
    }

    public func claimProcessingJobs(limit: Int, allowLowPriority: Bool) async -> [String] {
        cleanupOrphanedProcessingJobs()
        reclaimStaleRunningProcessingJobs()

        let descriptor = FetchDescriptor<ArticleProcessingJob>(
            sortBy: [
                SortDescriptor(\.priority, order: .reverse),
                SortDescriptor(\.updatedAt, order: .forward)
            ]
        )

        let now = Date()
        let minimumPriority = allowLowPriority ? 0 : 200
        let queuedJobs = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { job in
                job.status == .queued &&
                job.availableAt <= now &&
                job.priority >= minimumPriority
            }
            .prefix(limit)

        var claimed: [String] = []
        for job in queuedJobs {
            job.status = .running
            job.updatedAt = now
            claimed.append(job.key)
        }
        try? modelContext.save()
        return claimed
    }

    public func processingJob(articleID: String, stage: ArticleProcessingStage) async -> ArticleProcessingJob? {
        let key = ArticleProcessingJob.makeKey(articleID: articleID, stage: stage)
        return allProcessingJobs().first { $0.key == key }
    }

    public func completeProcessingJob(
        articleID: String,
        stage: ArticleProcessingStage,
        status: ArticleProcessingJobStatus,
        inputRevision: Int,
        error: String? = nil
    ) async throws {
        guard let job = await processingJob(articleID: articleID, stage: stage) else { return }
        job.status = status
        job.inputRevision = inputRevision
        job.lastError = error
        job.updatedAt = Date()
        if status == .failed {
            job.attemptCount += 1
            job.availableAt = Date().addingTimeInterval(60)
        }
        try modelContext.save()
    }

    public func markSummaryAttempt(
        id: String,
        status: ArticlePreparationStageStatus,
        revision: Int
    ) async throws {
        guard let article = await get(id: id) else { return }
        article.enrichmentPreparationStatusRaw = status.rawValue
        article.markSummaryPrepared(revision: revision)
        try modelContext.save()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
    }

    public func markImageAttempt(
        id: String,
        status: ArticlePreparationStageStatus,
        revision: Int
    ) async throws {
        guard let article = await get(id: id) else { return }
        article.imagePreparationStatusRaw = status.rawValue
        article.markImagePrepared(revision: revision)
        try modelContext.save()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
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
        let manualTags = (article.tags ?? [])
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let systemTagIDs = Set(article.systemTagIds)
        let systemTags: [String]
        if systemTagIDs.isEmpty {
            systemTags = []
        } else {
            let descriptor = FetchDescriptor<Tag>()
            let allTags = (try? modelContext.fetch(descriptor)) ?? []
            systemTags = allTags
                .filter { systemTagIDs.contains($0.id) }
                .map(\.name)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        var tags: [String] = []
        for value in manualTags + systemTags {
            guard !tags.contains(value) else { continue }
            tags.append(value)
        }

        return ArticleFallbackImageSnapshot(
            id: article.id,
            title: article.title,
            canonicalUrl: article.canonicalUrl,
            feedTitle: article.feed?.title,
            contentText: text,
            tags: tags,
            resolvedImageUrl: article.resolvedImageUrl,
            fallbackImageProvider: article.fallbackImageProvider
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
        if article.contentRevision == 0 {
            article.contentRevision = 1
        }
        article.refreshQueryState()
        modelContext.insert(article)
        try modelContext.save()
        try await enqueueMissingProcessingJobs(for: article.id)
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
        newArticle.queryIsVisible = false
        newArticle.contentRevision = 1
        newArticle.refreshQueryState()

        modelContext.insert(newArticle)
        try modelContext.save()
        try await enqueueMissingProcessingJobs(for: newArticle.id)
    }

    public func markRead(id: String, isRead: Bool) async throws {
        guard let article = await get(id: id) else { return }
        if isRead {
            article.markRead()
        } else {
            article.markUnread()
        }
        try modelContext.save()
        await rebuildTodaySnapshot()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
    }

    public func setReadingList(id: String, isSaved: Bool) async throws {
        guard let article = await get(id: id) else { return }
        if isSaved {
            article.addToReadingList()
        } else {
            article.removeFromReadingList()
        }
        try modelContext.save()
        ArticleChangeBus.postReadingListChanged()
        ArticleChangeBus.postArticleChanged(id: id)
    }

    public func react(id: String, value: Int?, reasonCodes: [String]?) async throws {
        guard let article = await get(id: id) else { return }
        article.setReaction(value: value, reasonCodes: reasonCodes)
        try modelContext.save()
        await rebuildTodaySnapshot()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
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
        article.markSummaryPrepared(revision: article.contentRevision)
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
        ArticleChangeBus.postArticleChanged(id: id)
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
        article.bumpContentRevision()

        // Recompute downstream outputs from the fuller article body.
        article.summaryText = nil
        article.cardSummaryText = nil
        article.summaryProvider = nil
        article.summaryModel = nil
        article.keyPointsJson = nil
        article.aiProcessedAt = nil
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        article.summaryPreparedRevision = 0

        article.score = nil
        article.scoreLabel = nil
        article.scoreConfidence = nil
        article.scorePreferenceConfidence = nil
        article.scoreWeightedAverage = nil
        article.scoreExplanation = nil
        article.scoreStatus = nil
        article.signalScoresJson = nil
        article.queryDisplayedScore = 0
        article.scorePreparedRevision = 0

        article.scoreAssistExplanation = nil
        article.scoreAssistProvider = nil
        article.scoreAssistModel = nil
        article.scoreAssistAdjustment = nil
        article.scoreAssistGeneratedAt = nil

        article.personalizationVersion = 0

        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
        try await enqueueMissingProcessingJobs(for: id)
        ArticleChangeBus.postArticleChanged(id: id)
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
        themeKey: String,
        photographerName: String? = nil,
        photographerProfileUrl: String? = nil,
        photoPageUrl: String? = nil
    ) async throws {
        guard let article = await get(id: id) else { return }
        guard article.imageUrl == nil, article.ogImageUrl == nil else { return }

        article.fallbackImageUrl = url
        article.fallbackImageProvider = provider
        article.fallbackImageTheme = themeKey
        article.fallbackImagePhotographerName = photographerName
        article.fallbackImagePhotographerProfileUrl = photographerProfileUrl
        article.fallbackImagePhotoPageUrl = photoPageUrl
        article.fallbackImageGeneratedAt = Date()
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.succeeded.rawValue
        article.markImagePrepared(revision: currentImagePreparationRevision)
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
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
        article.markImagePrepared(revision: currentImagePreparationRevision)
        applyPresentationReadyIfNeeded(to: article)
        try modelContext.save()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
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
        ArticleChangeBus.postArticleChanged(id: id)
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
            return [SortDescriptor(\.querySortDate, order: .reverse)]
        case .oldest:
            return [SortDescriptor(\.querySortDate, order: .forward)]
        case .scoreDesc:
            return [
                SortDescriptor(\.queryDisplayedScore, order: .reverse),
                SortDescriptor(\.querySortDate, order: .reverse)
            ]
        case .scoreAsc:
            return [
                SortDescriptor(\.queryDisplayedScore, order: .forward),
                SortDescriptor(\.querySortDate, order: .reverse)
            ]
        case .unreadFirst:
            return [SortDescriptor(\.querySortDate, order: .reverse)]
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
        article.refreshQueryState()
        guard article.queryIsVisible,
              article.presentationReadyAt == nil else {
            return
        }

        article.presentationReadyAt = Date()
    }

    private func pagedArticles(
        filter: ArticleFilter,
        cursor: ArticleListCursor?,
        limit: Int,
        requireReadingList: Bool
    ) async -> [Article] {
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !search.isEmpty {
            var boundedFilter = filter
            boundedFilter.searchText = search
            return await list(
                filter: boundedFilter,
                sort: .newest,
                limit: limit,
                offset: 0
            )
        }

        let chunkSize = max(limit * 4, 120)
        let maxPasses = 8
        var offset = 0
        var collected: [Article] = []

        for _ in 0..<maxPasses {
            var descriptor = basePagedDescriptor(
                presentationFilter: filter.presentationFilter,
                requireReadingList: requireReadingList
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = chunkSize

            let chunk = (try? modelContext.fetch(descriptor)) ?? []
            if chunk.isEmpty {
                break
            }

            let filtered = applyInMemoryFilters(chunk, filter: filter).filter { article in
                guard let cursor else { return true }
                return article.querySortDate < cursor.sortDate ||
                    (article.querySortDate == cursor.sortDate && article.id < cursor.articleID)
            }

            collected.append(contentsOf: filtered)
            if collected.count >= limit {
                break
            }

            offset += chunkSize
        }

        return Array(collected.prefix(limit))
    }

    private func basePagedDescriptor(
        presentationFilter: ArticlePresentationFilter,
        requireReadingList: Bool
    ) -> FetchDescriptor<Article> {
        let sortBy = [
            SortDescriptor(\Article.querySortDate, order: .reverse),
            SortDescriptor(\Article.id, order: .reverse)
        ]

        switch (presentationFilter, requireReadingList) {
        case (.pendingOnly, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false && article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (.pendingOnly, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false
                },
                sortBy: sortBy
            )
        case (_, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        default:
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == true
                },
                sortBy: sortBy
            )
        }
    }

    private func baseCountDescriptor(
        presentationFilter: ArticlePresentationFilter,
        requireReadingList: Bool
    ) -> FetchDescriptor<Article> {
        switch (presentationFilter, requireReadingList) {
        case (.pendingOnly, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false && article.readingListAddedAt != nil
                }
            )
        case (.pendingOnly, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false
                }
            )
        case (_, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.readingListAddedAt != nil
                }
            )
        default:
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == true
                }
            )
        }
    }

    private func unreadVisibleCount(publishedAfter: Date? = nil) -> Int {
        let threshold = publishedAfter ?? .distantPast
        let hasThreshold = publishedAfter != nil
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true &&
                article.queryIsUnreadQueueCandidate == true &&
                (!hasThreshold || article.querySortDate >= threshold)
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func highFitUnreadVisibleCount() -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true &&
                article.queryIsUnreadQueueCandidate == true &&
                article.queryDisplayedScore >= 4
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func readyVisibleCount() -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func topVisibleUnreadArticles(limit: Int) -> [Article] {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true &&
                article.queryIsUnreadQueueCandidate == true &&
                article.queryDisplayedScore >= 1
            },
            sortBy: [
                SortDescriptor(\.queryDisplayedScore, order: .reverse),
                SortDescriptor(\.querySortDate, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func ensureProcessingJobIfNeeded(
        articleID: String,
        stage: ArticleProcessingStage,
        priority: Int,
        inputRevision: Int,
        shouldQueue: Bool
    ) throws {
        let key = ArticleProcessingJob.makeKey(articleID: articleID, stage: stage)
        let existing = allProcessingJobs().first { $0.key == key }

        guard shouldQueue else {
            if let existing, existing.status == .queued || existing.status == .running {
                existing.status = .skipped
                existing.inputRevision = inputRevision
                existing.updatedAt = Date()
            }
            return
        }

        if let existing {
            guard existing.status != .queued || existing.inputRevision != inputRevision else {
                return
            }
            existing.status = .queued
            existing.priority = priority
            existing.availableAt = Date()
            existing.inputRevision = inputRevision
            existing.lastError = nil
            existing.updatedAt = Date()
            return
        }

        modelContext.insert(
            ArticleProcessingJob(
                articleID: articleID,
                stage: stage,
                priority: priority,
                inputRevision: inputRevision
            )
        )
    }

    private func existingProcessingJob(
        articleID: String,
        stage: ArticleProcessingStage
    ) throws -> ArticleProcessingJob? {
        let key = ArticleProcessingJob.makeKey(articleID: articleID, stage: stage)
        return allProcessingJobs().first { $0.key == key }
    }

    private func allProcessingJobs() -> [ArticleProcessingJob] {
        let descriptor = FetchDescriptor<ArticleProcessingJob>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func cleanupOrphanedProcessingJobs() {
        let articleDescriptor = FetchDescriptor<Article>()
        let liveArticleIDs = Set(((try? modelContext.fetch(articleDescriptor)) ?? []).map(\.id))

        let jobs = allProcessingJobs()

        for job in jobs where !liveArticleIDs.contains(job.articleID) {
            modelContext.delete(job)
        }
    }

    private func reclaimStaleRunningProcessingJobs(
        timeout: TimeInterval = 120
    ) {
        let cutoff = Date().addingTimeInterval(-timeout)
        let jobs = allProcessingJobs()

        for job in jobs
        where job.status == .running && job.updatedAt < cutoff {
            job.status = .queued
            job.updatedAt = Date()
            job.availableAt = Date()
            job.lastError = nil
        }
    }
}

#if DEBUG
extension LocalArticleRepository {
    public func processingDebugSnapshot() async -> ArticleProcessingDebugSnapshot {
        let jobs = allProcessingJobs()
        let articleTitles = Dictionary(
            uniqueKeysWithValues: (((try? modelContext.fetch(FetchDescriptor<Article>())) ?? []).map { article in
                (article.id, article.title)
            })
        )

        let runningJobs = jobs
            .filter { $0.status == .running }
            .sorted { $0.updatedAt > $1.updatedAt }

        let queuedJobs = jobs
            .filter { $0.status == .queued }
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority > $1.priority
                }
                return $0.updatedAt < $1.updatedAt
            }

        let failedJobs = jobs
            .filter { $0.status == .failed }
            .sorted { $0.updatedAt > $1.updatedAt }

        return ArticleProcessingDebugSnapshot(
            runningCount: runningJobs.count,
            queuedCount: queuedJobs.count,
            failedCount: failedJobs.count,
            pendingVisibleCount: await pendingVisibleArticleCount(),
            runningStageCounts: stageCounts(for: runningJobs),
            queuedStageCounts: stageCounts(for: queuedJobs),
            failedStageCounts: stageCounts(for: failedJobs),
            runningRows: runningJobs.map { debugRow(for: $0, articleTitles: articleTitles) },
            queuedRows: Array(queuedJobs.prefix(100)).map { debugRow(for: $0, articleTitles: articleTitles) },
            failedRows: Array(failedJobs.prefix(50)).map { debugRow(for: $0, articleTitles: articleTitles) }
        )
    }

    private func debugRow(
        for job: ArticleProcessingJob,
        articleTitles: [String: String?]
    ) -> ArticleProcessingDebugRow {
        ArticleProcessingDebugRow(
            id: job.key,
            articleID: job.articleID,
            articleTitle: articleTitles[job.articleID] ?? nil,
            stage: job.stage,
            status: job.status,
            priority: job.priority,
            attemptCount: job.attemptCount,
            availableAt: job.availableAt,
            updatedAt: job.updatedAt,
            lastError: job.lastError
        )
    }

    private func stageCounts(for jobs: [ArticleProcessingJob]) -> ArticleProcessingDebugStageCounts {
        ArticleProcessingDebugStageCounts(
            scoreAndTag: jobs.filter { $0.stage == .scoreAndTag }.count,
            fetchContent: jobs.filter { $0.stage == .fetchContent }.count,
            generateSummary: jobs.filter { $0.stage == .generateSummary }.count,
            resolveImage: jobs.filter { $0.stage == .resolveImage }.count
        )
    }
}
#endif
