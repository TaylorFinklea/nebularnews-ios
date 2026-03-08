import Foundation
import FeedKit
import SwiftData

// MARK: - Result Types

/// Aggregate result of a full poll cycle across all feeds.
public struct PollCycleResult: Sendable {
    public let feedsPolled: Int
    public let feedsSkipped: Int
    public let newArticles: Int
    public let errors: Int
    public let articlesDeleted: Int

    public init(feedsPolled: Int = 0, feedsSkipped: Int = 0, newArticles: Int = 0, errors: Int = 0, articlesDeleted: Int = 0) {
        self.feedsPolled = feedsPolled
        self.feedsSkipped = feedsSkipped
        self.newArticles = newArticles
        self.errors = errors
        self.articlesDeleted = articlesDeleted
    }
}

/// Result of polling a single feed.
public struct SingleFeedPollResult: Sendable {
    public let feedId: String
    public let feedTitle: String
    public let newArticles: Int
    public let wasNotModified: Bool
    public let error: String?

    public init(feedId: String, feedTitle: String, newArticles: Int = 0, wasNotModified: Bool = false, error: String? = nil) {
        self.feedId = feedId
        self.feedTitle = feedTitle
        self.newArticles = newArticles
        self.wasNotModified = wasNotModified
        self.error = error
    }
}

// MARK: - FeedPoller Actor

/// Orchestrates the feed ingestion pipeline: fetch → parse → dedupe → store.
///
/// Runs on its own actor isolation (not MainActor) to avoid blocking the UI.
/// Uses `FeedSnapshot` to receive feed data safely across actor boundaries.
public actor FeedPoller {
    private let fetcher: FeedFetcherProtocol
    private let feedRepo: LocalFeedRepository
    private let articleRepo: LocalArticleRepository
    private var isPolling = false

    public init(
        fetcher: FeedFetcherProtocol = URLSessionFeedFetcher(),
        feedRepo: LocalFeedRepository,
        articleRepo: LocalArticleRepository
    ) {
        self.fetcher = fetcher
        self.feedRepo = feedRepo
        self.articleRepo = articleRepo
    }

    // MARK: - Public API

    /// Poll all enabled feeds, returning aggregate stats.
    ///
    /// - Parameter bypassBackoff: If `true`, ignores error backoff (for user-initiated refresh).
    public func pollAllFeeds(bypassBackoff: Bool = false) async -> PollCycleResult {
        guard !isPolling else {
            return PollCycleResult()
        }
        isPolling = true
        defer { isPolling = false }

        let snapshots = await feedRepo.listSnapshots()
        let enabledFeeds = snapshots.filter(\.isEnabled)

        var totalPolled = 0
        var totalSkipped = 0
        var totalNew = 0
        var totalErrors = 0

        for snapshot in enabledFeeds {
            if !bypassBackoff && shouldSkipDueToBackoff(snapshot) {
                totalSkipped += 1
                continue
            }

            let result = await pollSingleFeedInternal(snapshot)
            totalPolled += 1

            if result.error != nil {
                totalErrors += 1
            }
            totalNew += result.newArticles
        }

        return PollCycleResult(
            feedsPolled: totalPolled,
            feedsSkipped: totalSkipped,
            newArticles: totalNew,
            errors: totalErrors
        )
    }

    /// Poll a single feed by ID (e.g., after adding a new feed for title auto-detection).
    public func pollFeed(id: String) async -> SingleFeedPollResult? {
        let snapshots = await feedRepo.listSnapshots()
        guard let snapshot = snapshots.first(where: { $0.id == id }) else {
            return nil
        }
        return await pollSingleFeedInternal(snapshot)
    }

    /// Delete articles older than `retentionDays` days using `publishedAt`
    /// when available, falling back to `fetchedAt`.
    public func cleanupOldArticles(retentionDays: Int) async -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        return (try? await articleRepo.deleteOlderThan(date: cutoff)) ?? 0
    }

    // MARK: - Internal Pipeline

    private func pollSingleFeedInternal(_ snapshot: FeedSnapshot) async -> SingleFeedPollResult {
        // 1. Fetch
        let fetchResult: FeedFetchResult
        do {
            fetchResult = try await fetcher.fetch(
                url: snapshot.feedUrl,
                etag: snapshot.etag,
                lastModified: snapshot.lastModified
            )
        } catch {
            let message = describeError(error)
            try? await feedRepo.recordPollError(id: snapshot.id, message: message)
            return SingleFeedPollResult(feedId: snapshot.id, feedTitle: snapshot.title, error: message)
        }

        // 2. Handle 304 Not Modified
        if fetchResult.wasNotModified {
            try? await feedRepo.recordPollSuccess(
                id: snapshot.id,
                etag: fetchResult.etag,
                lastModified: fetchResult.lastModified,
                hadNewItems: false
            )
            return SingleFeedPollResult(feedId: snapshot.id, feedTitle: snapshot.title, wasNotModified: true)
        }

        // 3. Parse with FeedKit
        let parsed: FeedKit.Feed
        do {
            let parser = FeedParser(data: fetchResult.data)
            let result = parser.parse()
            switch result {
            case .success(let feed):
                parsed = feed
            case .failure(let error):
                let message = "Parse error: \(error.localizedDescription)"
                try? await feedRepo.recordPollError(id: snapshot.id, message: message)
                return SingleFeedPollResult(feedId: snapshot.id, feedTitle: snapshot.title, error: message)
            }
        }

        // 4. Update feed metadata (title, siteUrl, iconUrl) if currently empty
        let metadata = FeedItemMapper.extractMetadata(from: parsed)
        try? await feedRepo.updateMetadata(
            id: snapshot.id,
            title: metadata.title,
            siteUrl: metadata.siteUrl,
            iconUrl: metadata.iconUrl
        )

        // 5. Extract articles and deduplicate
        let articles = FeedItemMapper.extractArticles(from: parsed)
        var newCount = 0

        for article in articles {
            // Check if we already have this article (by content hash)
            let existing = await articleRepo.getByHash(article.contentHash)
            if existing == nil {
                do {
                    try await articleRepo.insertForFeed(feedId: snapshot.id, article: article)
                    newCount += 1
                } catch {
                    // Log but don't fail the whole feed
                    continue
                }
            }
        }

        // 6. Record success
        try? await feedRepo.recordPollSuccess(
            id: snapshot.id,
            etag: fetchResult.etag,
            lastModified: fetchResult.lastModified,
            hadNewItems: newCount > 0
        )

        let displayTitle = metadata.title ?? snapshot.title
        return SingleFeedPollResult(feedId: snapshot.id, feedTitle: displayTitle, newArticles: newCount)
    }

    // MARK: - Backoff Logic

    /// Backoff schedule based on consecutive errors:
    /// 1 → 5min, 2 → 15min, 3 → 1hr, 4 → 4hr, 5+ → 12hr
    private func shouldSkipDueToBackoff(_ snapshot: FeedSnapshot) -> Bool {
        guard snapshot.consecutiveErrors > 0,
              let lastPolled = snapshot.lastPolledAt else {
            return false
        }

        let backoffMinutes: Int
        switch snapshot.consecutiveErrors {
        case 1: backoffMinutes = 5
        case 2: backoffMinutes = 15
        case 3: backoffMinutes = 60
        case 4: backoffMinutes = 240
        default: backoffMinutes = 720
        }

        let nextRetry = lastPolled.addingTimeInterval(TimeInterval(backoffMinutes * 60))
        return Date() < nextRetry
    }

    private func describeError(_ error: Error) -> String {
        switch error {
        case FeedFetchError.invalidURL:
            return "Invalid feed URL"
        case FeedFetchError.httpError(let code):
            return "HTTP \(code)"
        case FeedFetchError.timeout:
            return "Request timed out"
        case FeedFetchError.networkError(let msg):
            return "Network error: \(msg)"
        default:
            return error.localizedDescription
        }
    }
}
