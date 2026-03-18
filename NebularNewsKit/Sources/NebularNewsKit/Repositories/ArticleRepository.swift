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

public enum ArticleStorageScope: String, Sendable, CaseIterable, Hashable {
    case active
    case archived
    case all
}

public enum ArticleSort: String, Sendable, CaseIterable {
    case newest, oldest, scoreDesc, scoreAsc, unreadFirst
}

public struct ArticleListCursor: Codable, Hashable, Sendable {
    public let sortDate: Date
    public let articleID: String
    public let displayedScore: Int

    public init(sortDate: Date, articleID: String, displayedScore: Int = 0) {
        self.sortDate = sortDate
        self.articleID = articleID
        self.displayedScore = displayedScore
    }
}

public struct ArticleFilter: Sendable {
    public var presentationFilter: ArticlePresentationFilter = .all
    public var readFilter: ArticleReadFilter = .all
    public var storageScope: ArticleStorageScope = .all
    public var readingListOnly = false
    public var minScore: Int?
    public var maxScore: Int?
    public var publishedAfter: Date?
    public var publishedBefore: Date?
    public var feedId: String?
    public var tagIds: [String] = []
    public var searchText: String?

    public init() {}
}

public struct ArticleStorageEnforcementResult: Sendable {
    public let archivedByAge: Int
    public let archivedByFeedLimit: Int
    public let restored: Int
    public let deleted: Int

    public init(
        archivedByAge: Int = 0,
        archivedByFeedLimit: Int = 0,
        restored: Int = 0,
        deleted: Int = 0
    ) {
        self.archivedByAge = archivedByAge
        self.archivedByFeedLimit = archivedByFeedLimit
        self.restored = restored
        self.deleted = deleted
    }

    public var archived: Int {
        archivedByAge + archivedByFeedLimit
    }
}

// MARK: - Protocol

public protocol ArticleRepositoryProtocol: Sendable {
    func list(filter: ArticleFilter, sort: ArticleSort, limit: Int, offset: Int) async -> [Article]
    func listVisibleArticles(filter: ArticleFilter, sort: ArticleSort, limit: Int, offset: Int) async -> [Article]
    func count(filter: ArticleFilter) async -> Int
    func countVisibleArticles(filter: ArticleFilter) async -> Int
    func listFeedPage(filter: ArticleFilter, sort: ArticleSort, cursor: ArticleListCursor?, limit: Int) async -> [Article]
    func countFeed(filter: ArticleFilter) async -> Int
    func fetchTodaySnapshot() async -> TodaySnapshot
    func rebuildTodaySnapshot() async
    func fetchReadingListPage(filter: ArticleFilter, cursor: ArticleListCursor?, limit: Int) async -> [Article]
    func listArticles(ids: [String]) async -> [Article]
    func activeArticleCountsByFeed() async -> [String: Int]
    func feedReputation(feedKey: String?) async -> FeedReputation
    func listFeedReputationSummaries() async -> [FeedReputationSummary]
    func listLowestReputationFeeds(limit: Int) async -> [FeedReputationSummary]
    func get(id: String) async -> Article?
    func getByHash(_ hash: String) async -> Article?
    func enrichmentSnapshot(id: String) async -> ArticleSnapshot?
    func contentFetchCandidate(id: String) async -> ArticleContentFetchCandidate?
    func listContentFetchCandidates(limit: Int, recentOnly: Bool) async -> [ArticleContentFetchCandidate]
    func pendingVisibleArticleCount() async -> Int
    func processingQueueHealth() async -> ArticleProcessingQueueHealth
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
    func syncStandaloneUserState(id: String) async throws
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
    func enforceStoragePolicy(
        archiveAfterDays: Int,
        deleteArchivedAfterDays: Int,
        maxActiveUnsavedPerFeed: Int
    ) async throws -> ArticleStorageEnforcementResult
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
        if visibleFilter.storageScope == .all {
            visibleFilter.storageScope = .active
        }
        return await list(filter: visibleFilter, sort: sort, limit: limit, offset: offset)
    }

    public func count(filter: ArticleFilter) async -> Int {
        let searchText = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsInMemoryFiltering =
            filter.readFilter != .all ||
            filter.minScore != nil ||
            filter.maxScore != nil ||
            filter.publishedAfter != nil ||
            filter.publishedBefore != nil ||
            filter.feedId != nil ||
            !filter.tagIds.isEmpty ||
            !((searchText?.isEmpty) ?? true)

        let baseDescriptor = baseCountDescriptor(
            presentationFilter: filter.presentationFilter,
            storageScope: filter.storageScope,
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
        if visibleFilter.storageScope == .all {
            visibleFilter.storageScope = .active
        }
        return await count(filter: visibleFilter)
    }

    public func listFeedPage(
        filter: ArticleFilter,
        sort: ArticleSort,
        cursor: ArticleListCursor?,
        limit: Int
    ) async -> [Article] {
        var feedFilter = filter
        feedFilter.presentationFilter = .readyOnly
        if feedFilter.storageScope == .all {
            feedFilter.storageScope = .active
        }
        return await pagedArticles(
            filter: feedFilter,
            sort: sort,
            cursor: cursor,
            limit: limit,
            requireReadingList: false
        )
    }

    public func countFeed(filter: ArticleFilter) async -> Int {
        var feedFilter = filter
        feedFilter.presentationFilter = .readyOnly
        if feedFilter.storageScope == .all {
            feedFilter.storageScope = .active
        }
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
            sort: .newest,
            cursor: cursor,
            limit: limit,
            requireReadingList: true
        )
    }

    public func listArticles(ids: [String]) async -> [Article] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public func activeArticleCountsByFeed() async -> [String: Int] {
        let descriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(descriptor)) ?? []

        return Dictionary(
            grouping: articles.filter { !$0.queryIsArchived }
        ) { article in
            article.queryFeedID
        }
        .reduce(into: [String: Int]()) { partial, element in
            guard let feedID = element.key else { return }
            partial[feedID] = element.value.count
        }
    }

    public func feedReputation(feedKey: String?) async -> FeedReputation {
        guard let feedKey, !feedKey.isEmpty else {
            return computeFeedReputation(feedbackCount: 0, weightedFeedbackCount: 0, ratingSum: 0)
        }

        var accumulator = FeedReputationAccumulator()
        for state in allSyncedArticleStates() where state.feedKey == feedKey {
            accumulator.add(
                reactionValue: state.reactionValue,
                serializedReasonCodes: state.reactionReasonCodes,
                feedbackAt: state.reactionUpdatedAt ?? state.updatedAt
            )
        }
        return accumulator.reputation
    }

    public func listFeedReputationSummaries() async -> [FeedReputationSummary] {
        allFeedReputationSummaries()
            .sorted {
                let lhsName = preferredFeedDisplayName(title: $0.title, feedURL: $0.feedURL)
                let rhsName = preferredFeedDisplayName(title: $1.title, feedURL: $1.feedURL)
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
    }

    public func listLowestReputationFeeds(limit: Int) async -> [FeedReputationSummary] {
        Array(
            allFeedReputationSummaries()
                .filter { $0.feedbackCount > 0 }
                .sorted {
                    if $0.score != $1.score {
                        return $0.score < $1.score
                    }
                    if $0.feedbackCount != $1.feedbackCount {
                        return $0.feedbackCount > $1.feedbackCount
                    }

                    let lhsName = preferredFeedDisplayName(title: $0.title, feedURL: $0.feedURL)
                    let rhsName = preferredFeedDisplayName(title: $1.title, feedURL: $1.feedURL)
                    return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
                }
                .prefix(max(limit, 0))
        )
    }

    public func pendingVisibleArticleCount() async -> Int {
        await processingQueueHealth().pendingVisibleCount
    }

    public func processingQueueHealth() async -> ArticleProcessingQueueHealth {
        let hiddenArticleIDs = Set(
            (((try? modelContext.fetch(FetchDescriptor<Article>())) ?? [])
                .filter { $0.queryIsVisible == false && $0.queryIsArchived == false }
                .map(\.id))
        )
        let jobs = allProcessingJobs()

        let queuedScoreJobs = jobs.filter {
            $0.stage == .scoreAndTag && $0.status == .queued
        }
        let runningScoreJobs = jobs.filter {
            $0.stage == .scoreAndTag && $0.status == .running
        }
        let pendingVisibleCount =
            queuedScoreJobs.count(where: { hiddenArticleIDs.contains($0.articleID) }) +
            runningScoreJobs.count(where: { hiddenArticleIDs.contains($0.articleID) })

        return ArticleProcessingQueueHealth(
            pendingVisibleCount: pendingVisibleCount,
            queuedScoreJobCount: queuedScoreJobs.count,
            runningScoreJobCount: runningScoreJobs.count
        )
    }

    public func backfillMissingProcessingJobsForInvisibleArticles(limit: Int) async throws -> Int {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> {
                $0.queryIsVisible == false &&
                $0.queryIsArchived == false
            },
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
                $0.queryIsArchived == false &&
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

            let changed = try ensureProcessingJobIfNeeded(
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

            if changed,
               previousQueuedJob?.status != .queued,
               refreshedJob?.status == .queued {
                touched += 1
            }
        }

        try modelContext.save()
        if touched > 0 {
            ArticleChangeBus.postProcessingQueueChanged()
        }
        return touched
    }

    public func enqueueMissingProcessingJobs(for articleID: String) async throws {
        guard let article = await get(id: articleID) else { return }
        let changed = try syncProcessingJobs(for: article)
        try modelContext.save()
        if changed {
            ArticleChangeBus.postProcessingQueueChanged()
        }
    }

    public func claimProcessingJobs(limit: Int, allowLowPriority: Bool) async -> [String] {
        cleanupOrphanedProcessingJobs()
        let removedArchived = cleanupArchivedProcessingJobs()
        let reclaimed = reclaimStaleRunningProcessingJobs()

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
        if reclaimed || removedArchived || !claimed.isEmpty {
            ArticleChangeBus.postProcessingQueueChanged()
        }
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
        if stage == .scoreAndTag {
            ArticleChangeBus.postProcessingQueueChanged()
        }
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
                !article.isArchived &&
                (!recentOnly || article.retentionReferenceDate >= recentCutoff)
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
        applySyncedArticleStateIfPresent(to: article)
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
        applySyncedArticleStateIfPresent(to: newArticle)

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
        upsertSyncedArticleState(from: article, updatedAt: article.userStateUpdatedAt ?? Date())
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
        upsertSyncedArticleState(from: article, updatedAt: article.userStateUpdatedAt ?? Date())
        try modelContext.save()
        ArticleChangeBus.postReadingListChanged()
        ArticleChangeBus.postArticleChanged(id: id)
    }

    public func react(id: String, value: Int?, reasonCodes: [String]?) async throws {
        guard let article = await get(id: id) else { return }
        article.setReaction(value: value, reasonCodes: reasonCodes)
        upsertSyncedArticleState(from: article, updatedAt: article.userStateUpdatedAt ?? Date())
        try modelContext.save()
        await rebuildTodaySnapshot()
        ArticleChangeBus.postFeedPageMightChange()
        ArticleChangeBus.postArticleChanged(id: id)
    }

    public func syncStandaloneUserState(id: String) async throws {
        guard let article = await get(id: id) else { return }
        article.refreshQueryState()
        upsertSyncedArticleState(from: article, updatedAt: article.userStateUpdatedAt ?? Date())
        try modelContext.save()
        await rebuildTodaySnapshot()
        ArticleChangeBus.postArticleChanged(id: id)
        ArticleChangeBus.postReadingListChanged()
        ArticleChangeBus.postFeedPageMightChange()
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
            guard !article.isArchived else { return nil }
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

    public func enforceStoragePolicy(
        archiveAfterDays: Int,
        deleteArchivedAfterDays: Int,
        maxActiveUnsavedPerFeed: Int
    ) async throws -> ArticleStorageEnforcementResult {
        let archiveWindow = max(archiveAfterDays, 1)
        let deleteWindow = max(deleteArchivedAfterDays, 1)
        let feedLimit = max(maxActiveUnsavedPerFeed, 1)
        let now = Date()
        let calendar = Calendar.current
        let archiveCutoff = calendar.date(byAdding: .day, value: -archiveWindow, to: now) ?? now
        let deleteCutoff = calendar.date(byAdding: .day, value: -deleteWindow, to: now) ?? now

        let descriptor = FetchDescriptor<Article>()
        let allArticles = try modelContext.fetch(descriptor)

        var archivedByAge = 0
        var archivedByFeedLimit = 0
        var restored = 0
        var deleted = 0

        for article in allArticles where article.isArchived && article.retentionReferenceDate >= archiveCutoff {
            article.restoreFromArchive()
            _ = try syncProcessingJobs(for: article)
            restored += 1
        }

        for article in allArticles where !article.isArchived && article.retentionReferenceDate < archiveCutoff {
            article.archive(reason: .ageLimit, at: now)
            _ = try syncProcessingJobs(for: article)
            archivedByAge += 1
        }

        let activeByFeed = Dictionary(grouping: allArticles.filter { !$0.isArchived }) { article in
            article.queryFeedID
        }

        for (feedID, articles) in activeByFeed {
            guard feedID != nil else { continue }

            let unsavedArticles = articles
                .filter { !$0.isInReadingList }
                .sorted { lhs, rhs in
                    if lhs.retentionReferenceDate != rhs.retentionReferenceDate {
                        return lhs.retentionReferenceDate > rhs.retentionReferenceDate
                    }
                    return lhs.fetchedAt > rhs.fetchedAt
                }

            guard unsavedArticles.count > feedLimit else { continue }

            for article in unsavedArticles.dropFirst(feedLimit) where !article.isArchived {
                article.archive(reason: .feedLimit, at: now)
                _ = try syncProcessingJobs(for: article)
                archivedByFeedLimit += 1
            }
        }

        for article in allArticles where article.isArchived && !article.isInReadingList {
            let archiveAnchor = article.archivedAt ?? now
            guard archiveAnchor <= deleteCutoff else { continue }
            _ = removeProcessingJobs(for: article.id)
            modelContext.delete(article)
            deleted += 1
        }

        let changed = archivedByAge > 0 || archivedByFeedLimit > 0 || restored > 0 || deleted > 0
        if changed {
            try modelContext.save()
            await rebuildTodaySnapshot()
            ArticleChangeBus.postFeedPageMightChange()
            ArticleChangeBus.postProcessingQueueChanged()
        }

        return ArticleStorageEnforcementResult(
            archivedByAge: archivedByAge,
            archivedByFeedLimit: archivedByFeedLimit,
            restored: restored,
            deleted: deleted
        )
    }

    // MARK: - Private

    private func sortDescriptors(for sort: ArticleSort) -> [SortDescriptor<Article>] {
        switch sort {
        case .newest:
            return [
                SortDescriptor(\.querySortDate, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        case .oldest:
            return [
                SortDescriptor(\.querySortDate, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        case .scoreDesc:
            return [
                SortDescriptor(\.queryDisplayedScore, order: .reverse),
                SortDescriptor(\.querySortDate, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        case .scoreAsc:
            return [
                SortDescriptor(\.queryDisplayedScore, order: .forward),
                SortDescriptor(\.querySortDate, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        case .unreadFirst:
            return [
                SortDescriptor(\.querySortDate, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
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

        switch filter.storageScope {
        case .active:
            result = result.filter { !$0.queryIsArchived }
        case .archived:
            result = result.filter(\.queryIsArchived)
        case .all:
            break
        }

        if let feedId = filter.feedId {
            result = result.filter { $0.queryFeedID == feedId }
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

        if let publishedBefore = filter.publishedBefore {
            result = result.filter {
                ($0.publishedAt ?? $0.fetchedAt) <= publishedBefore
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
        sort: ArticleSort,
        cursor: ArticleListCursor?,
        limit: Int,
        requireReadingList: Bool
    ) async -> [Article] {
        if let search = filter.searchText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !search.isEmpty {
            var boundedFilter = filter
            boundedFilter.searchText = search
            let allMatching = await list(
                filter: boundedFilter,
                sort: sort,
                limit: 10_000,
                offset: 0
            )
            let filtered = allMatching.filter { article in
                guard let cursor else { return true }
                return isArticleAfterCursor(article, cursor: cursor, sort: sort)
            }
            return Array(filtered.prefix(limit))
        }

        let chunkSize = max(limit * 4, 120)
        let maxPasses = 8
        var offset = 0
        var collected: [Article] = []

        for _ in 0..<maxPasses {
            var descriptor = basePagedDescriptor(
                presentationFilter: filter.presentationFilter,
                storageScope: filter.storageScope,
                requireReadingList: requireReadingList,
                sort: sort
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = chunkSize

            let chunk = (try? modelContext.fetch(descriptor)) ?? []
            if chunk.isEmpty {
                break
            }

            let filtered = applyInMemoryFilters(chunk, filter: filter).filter { article in
                guard let cursor else { return true }
                return isArticleAfterCursor(article, cursor: cursor, sort: sort)
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
        storageScope: ArticleStorageScope,
        requireReadingList: Bool,
        sort: ArticleSort
    ) -> FetchDescriptor<Article> {
        let sortBy = sortDescriptors(for: sort)

        switch (presentationFilter, storageScope, requireReadingList) {
        case (.pendingOnly, .active, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false &&
                    article.queryIsArchived == false &&
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (.pendingOnly, .active, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false &&
                    article.queryIsArchived == false
                },
                sortBy: sortBy
            )
        case (.pendingOnly, .archived, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (.pendingOnly, .archived, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true
                },
                sortBy: sortBy
            )
        case (.pendingOnly, .all, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false && article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (.pendingOnly, .all, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false
                },
                sortBy: sortBy
            )
        case (_, .active, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == false &&
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (_, .active, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == true &&
                    article.queryIsArchived == false
                },
                sortBy: sortBy
            )
        case (_, .archived, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (.all, .archived, false), (.readyOnly, .archived, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.queryIsVisible == true
                },
                sortBy: sortBy
            )
        case (_, .all, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.readingListAddedAt != nil
                },
                sortBy: sortBy
            )
        case (_, .all, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == true
                },
                sortBy: sortBy
            )
        }
    }

    private func isArticleAfterCursor(
        _ article: Article,
        cursor: ArticleListCursor,
        sort: ArticleSort
    ) -> Bool {
        switch sort {
        case .newest:
            if article.querySortDate != cursor.sortDate {
                return article.querySortDate < cursor.sortDate
            }
            return article.id < cursor.articleID
        case .oldest:
            if article.querySortDate != cursor.sortDate {
                return article.querySortDate > cursor.sortDate
            }
            return article.id > cursor.articleID
        case .scoreDesc:
            if article.queryDisplayedScore != cursor.displayedScore {
                return article.queryDisplayedScore < cursor.displayedScore
            }
            if article.querySortDate != cursor.sortDate {
                return article.querySortDate < cursor.sortDate
            }
            return article.id < cursor.articleID
        case .scoreAsc:
            if article.queryDisplayedScore != cursor.displayedScore {
                return article.queryDisplayedScore > cursor.displayedScore
            }
            if article.querySortDate != cursor.sortDate {
                return article.querySortDate < cursor.sortDate
            }
            return article.id < cursor.articleID
        case .unreadFirst:
            if article.querySortDate != cursor.sortDate {
                return article.querySortDate < cursor.sortDate
            }
            return article.id < cursor.articleID
        }
    }

    private func baseCountDescriptor(
        presentationFilter: ArticlePresentationFilter,
        storageScope: ArticleStorageScope,
        requireReadingList: Bool
    ) -> FetchDescriptor<Article> {
        switch (presentationFilter, storageScope, requireReadingList) {
        case (.pendingOnly, .active, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false &&
                    article.queryIsArchived == false &&
                    article.readingListAddedAt != nil
                }
            )
        case (.pendingOnly, .active, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false &&
                    article.queryIsArchived == false
                }
            )
        case (.pendingOnly, .archived, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.readingListAddedAt != nil
                }
            )
        case (.pendingOnly, .archived, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true
                }
            )
        case (.pendingOnly, .all, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false && article.readingListAddedAt != nil
                }
            )
        case (.pendingOnly, .all, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == false
                }
            )
        case (_, .active, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == false &&
                    article.readingListAddedAt != nil
                }
            )
        case (_, .active, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsVisible == true &&
                    article.queryIsArchived == false
                }
            )
        case (_, .archived, true):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.readingListAddedAt != nil
                }
            )
        case (.all, .archived, false), (.readyOnly, .archived, false):
            return FetchDescriptor<Article>(
                predicate: #Predicate<Article> { article in
                    article.queryIsArchived == true &&
                    article.queryIsVisible == true
                }
            )
        case (_, .all, true):
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
                article.queryIsArchived == false &&
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
                article.queryIsArchived == false &&
                article.queryIsUnreadQueueCandidate == true &&
                article.queryDisplayedScore >= 4
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func readyVisibleCount() -> Int {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true &&
                article.queryIsArchived == false
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func topVisibleUnreadArticles(limit: Int) -> [Article] {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.queryIsVisible == true &&
                article.queryIsArchived == false &&
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
    ) throws -> Bool {
        let key = ArticleProcessingJob.makeKey(articleID: articleID, stage: stage)
        let existing = allProcessingJobs().first { $0.key == key }

        guard shouldQueue else {
            if let existing, existing.status == .queued || existing.status == .running {
                existing.status = .skipped
                existing.inputRevision = inputRevision
                existing.updatedAt = Date()
                return true
            }
            return false
        }

        if let existing {
            guard existing.status != .queued || existing.inputRevision != inputRevision else {
                return false
            }
            existing.status = .queued
            existing.priority = priority
            existing.availableAt = Date()
            existing.inputRevision = inputRevision
            existing.lastError = nil
            existing.updatedAt = Date()
            return true
        }

        modelContext.insert(
            ArticleProcessingJob(
                articleID: articleID,
                stage: stage,
                priority: priority,
                inputRevision: inputRevision
            )
        )
        return true
    }

    private func syncProcessingJobs(for article: Article) throws -> Bool {
        if article.isArchived {
            return removeProcessingJobs(for: article.id)
        }

        let scoreChanged = try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .scoreAndTag,
            priority: 300,
            inputRevision: max(article.contentRevision, currentPersonalizationVersion),
            shouldQueue: article.scorePreparedRevision < max(article.contentRevision, currentPersonalizationVersion) ||
                article.queryIsVisible == false
        )

        let contentChanged = try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .fetchContent,
            priority: 200,
            inputRevision: article.contentRevision,
            shouldQueue: article.contentFetchAttemptedAt == nil && article.needsContentFetch()
        )

        let summaryChanged = try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .generateSummary,
            priority: 100,
            inputRevision: article.contentRevision,
            shouldQueue: article.summaryPreparedRevision < article.contentRevision
        )

        let imageChanged = try ensureProcessingJobIfNeeded(
            articleID: article.id,
            stage: .resolveImage,
            priority: 150,
            inputRevision: currentImagePreparationRevision,
            shouldQueue: article.imageUrl == nil &&
                article.ogImageUrl == nil &&
                article.imagePreparedRevision < currentImagePreparationRevision
        )

        return scoreChanged || contentChanged || summaryChanged || imageChanged
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

    @discardableResult
    private func removeProcessingJobs(for articleID: String) -> Bool {
        let jobs = allProcessingJobs().filter { $0.articleID == articleID }
        guard !jobs.isEmpty else { return false }
        for job in jobs {
            modelContext.delete(job)
        }
        return true
    }

    private func cleanupOrphanedProcessingJobs() {
        let articleDescriptor = FetchDescriptor<Article>()
        let liveArticleIDs = Set(((try? modelContext.fetch(articleDescriptor)) ?? []).map(\.id))

        let jobs = allProcessingJobs()

        for job in jobs where !liveArticleIDs.contains(job.articleID) {
            modelContext.delete(job)
        }
    }

    private func cleanupArchivedProcessingJobs() -> Bool {
        let articleDescriptor = FetchDescriptor<Article>()
        let archivedArticleIDs = Set(
            ((try? modelContext.fetch(articleDescriptor)) ?? [])
                .filter(\.isArchived)
                .map(\.id)
        )

        guard !archivedArticleIDs.isEmpty else { return false }

        let jobs = allProcessingJobs()
        var removed = false
        for job in jobs where archivedArticleIDs.contains(job.articleID) {
            modelContext.delete(job)
            removed = true
        }
        return removed
    }

    private func reclaimStaleRunningProcessingJobs(
        timeout: TimeInterval = 120
    ) -> Bool {
        let cutoff = Date().addingTimeInterval(-timeout)
        let jobs = allProcessingJobs()
        var reclaimed = false

        for job in jobs
        where job.status == .running && job.updatedAt < cutoff {
            job.status = .queued
            job.updatedAt = Date()
            job.availableAt = Date()
            job.lastError = nil
            reclaimed = true
        }

        return reclaimed
    }

    private func allSyncedArticleStates() -> [SyncedArticleState] {
        (try? modelContext.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
    }

    private func allFeedReputationSummaries() -> [FeedReputationSummary] {
        let localFeeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        let syncedSubscriptions = (try? modelContext.fetch(FetchDescriptor<SyncedFeedSubscription>())) ?? []
        let syncedStates = allSyncedArticleStates()

        let localByKey = Dictionary(
            uniqueKeysWithValues: localFeeds.compactMap { feed -> (String, Feed)? in
                feed.refreshIdentity()
                guard !feed.feedKey.isEmpty else { return nil }
                return (feed.feedKey, feed)
            }
        )
        let subscriptionsByKey = Dictionary(uniqueKeysWithValues: syncedSubscriptions.map { ($0.feedKey, $0) })

        var accumulators: [String: FeedReputationAccumulator] = [:]
        for state in syncedStates {
            guard !state.feedKey.isEmpty else { continue }
            var accumulator = accumulators[state.feedKey] ?? FeedReputationAccumulator()
            accumulator.add(
                reactionValue: state.reactionValue,
                serializedReasonCodes: state.reactionReasonCodes,
                feedbackAt: state.reactionUpdatedAt ?? state.updatedAt
            )
            accumulators[state.feedKey] = accumulator
        }

        let allFeedKeys = Set(localByKey.keys)
            .union(subscriptionsByKey.keys)
            .union(accumulators.keys)

        return allFeedKeys.map { feedKey in
            let localFeed = localByKey[feedKey]
            let subscription = subscriptionsByKey[feedKey]
            let accumulator = accumulators[feedKey] ?? FeedReputationAccumulator()
            let reputation = accumulator.reputation

            let localTitle = localFeed?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let syncedTitle = subscription?.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (localTitle?.isEmpty == false ? localTitle : nil)
                ?? (syncedTitle?.isEmpty == false ? syncedTitle : nil)
                ?? subscription?.feedURL
                ?? localFeed?.feedUrl
                ?? feedKey
            let feedURL = localFeed?.feedUrl ?? subscription?.feedURL ?? feedKey
            let isEnabled = localFeed?.isEnabled ?? subscription?.isEnabled ?? true

            return FeedReputationSummary(
                feedKey: feedKey,
                feedID: localFeed?.id,
                title: title,
                feedURL: feedURL,
                isEnabled: isEnabled,
                feedbackCount: reputation.feedbackCount,
                weightedFeedbackCount: reputation.weightedFeedbackCount,
                ratingSum: reputation.ratingSum,
                score: reputation.score,
                normalizedScore: reputation.normalizedScore,
                lastFeedbackAt: accumulator.lastFeedbackAt
            )
        }
    }

    private func preferredFeedDisplayName(title: String, feedURL: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? feedURL : trimmedTitle
    }

    private func syncedArticleState(articleKey: String) -> SyncedArticleState? {
        guard !articleKey.isEmpty else { return nil }
        var descriptor = FetchDescriptor<SyncedArticleState>(
            predicate: #Predicate<SyncedArticleState> { $0.articleKey == articleKey }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func applySyncedArticleStateIfPresent(to article: Article) {
        guard !article.articleKey.isEmpty,
              let synced = syncedArticleState(articleKey: article.articleKey)
        else {
            return
        }

        if synced.feedKey.isEmpty, let localFeedKey = article.feed?.feedKey, !localFeedKey.isEmpty {
            synced.feedKey = localFeedKey
        }

        article.isRead = synced.isRead
        article.readAt = synced.readAt
        article.dismissedAt = synced.dismissedAt
        article.readingListAddedAt = synced.readingListAddedAt
        article.reactionValue = synced.reactionValue
        article.reactionReasonCodes = synced.reactionReasonCodes
        article.reactionUpdatedAt = synced.reactionUpdatedAt ?? (synced.reactionValue == nil ? nil : synced.updatedAt)
        article.refreshQueryState()
    }

    private func upsertSyncedArticleState(from article: Article, updatedAt: Date) {
        article.refreshQueryState()
        guard !article.articleKey.isEmpty else {
            return
        }

        let row = syncedArticleState(articleKey: article.articleKey) ?? {
            let newRow = SyncedArticleState(articleKey: article.articleKey)
            modelContext.insert(newRow)
            return newRow
        }()

        row.isRead = article.isRead
        row.readAt = article.readAt
        row.dismissedAt = article.dismissedAt
        row.readingListAddedAt = article.readingListAddedAt
        row.reactionValue = article.reactionValue
        row.reactionReasonCodes = article.reactionReasonCodes
        row.feedKey = article.feed?.feedKey ?? row.feedKey
        row.reactionUpdatedAt = article.reactionUpdatedAt
        row.updatedAt = updatedAt
    }
}

#if DEBUG
extension LocalArticleRepository {
    public func standaloneSyncDebugSnapshot() async -> StandaloneSyncDebugSnapshot {
        let syncedFeeds = (try? modelContext.fetch(FetchDescriptor<SyncedFeedSubscription>())) ?? []
        let syncedStates = (try? modelContext.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
        let syncedPreferencesRow = try? modelContext.fetch(FetchDescriptor<SyncedPreferences>()).first
        let localFeeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        let localArticles = (try? modelContext.fetch(FetchDescriptor<Article>())) ?? []

        let feedRows = syncedFeeds
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map {
                StandaloneSyncDebugFeedRow(
                    id: $0.id,
                    feedKey: $0.feedKey,
                    feedURL: $0.feedURL,
                    titleOverride: $0.titleOverride,
                    isEnabled: $0.isEnabled,
                    updatedAt: $0.updatedAt
                )
            }

        let articleStateRows = syncedStates
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map {
                StandaloneSyncDebugArticleStateRow(
                    id: $0.id,
                    articleKey: $0.articleKey,
                    isRead: $0.isRead,
                    isDismissed: $0.dismissedAt != nil,
                    isSaved: $0.readingListAddedAt != nil,
                    reactionValue: $0.reactionValue,
                    updatedAt: $0.updatedAt
                )
            }

        let syncedPreferences = syncedPreferencesRow.map {
            StandaloneSyncDebugPreferences(
                archiveAfterDays: $0.archiveAfterDays,
                deleteArchivedAfterDays: $0.deleteArchivedAfterDays,
                maxArticlesPerFeed: $0.maxArticlesPerFeed,
                searchArchivedByDefault: $0.searchArchivedByDefault,
                updatedAt: $0.updatedAt
            )
        }

        return StandaloneSyncDebugSnapshot(
            syncedFeedSubscriptionCount: syncedFeeds.count,
            syncedArticleStateCount: syncedStates.count,
            localFeedCount: localFeeds.count,
            localArticleCount: localArticles.count,
            localReadCount: localArticles.filter(\.isRead).count,
            localDismissedCount: localArticles.filter { $0.dismissedAt != nil }.count,
            localSavedCount: localArticles.filter(\.isInReadingList).count,
            localReactedCount: localArticles.filter { $0.reactionValue != nil }.count,
            syncedPreferences: syncedPreferences,
            feedRows: Array(feedRows),
            articleStateRows: Array(articleStateRows)
        )
    }

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
