import Foundation
import Observation
import SwiftData
import NebularNewsKit

struct FeedOPMLExportPayload {
    let document: FeedOPMLDocument
    let defaultFilename: String
}

@Observable
@MainActor
final class FeedListViewModel {
    let feedRepo: LocalFeedRepository
    private let articleRepo: LocalArticleRepository
    private let settingsRepo: LocalSettingsRepository
    private let modelContainer: ModelContainer
    private var poller: FeedPoller?
    private(set) var activeArticleCountsByFeed: [String: Int] = [:]
    private(set) var feedReputationsByFeedKey: [String: FeedReputationSummary] = [:]
    private(set) var lowestReputationFeeds: [FeedReputationSummary] = []

    var feeds: [Feed] = []
    var isLoading = false
    var isPolling = false
    var isPreparing = false
    var showAddSheet = false
    var errorMessage: String?
    var lastPollMessage: String?

    init(modelContext: ModelContext) {
        let container = modelContext.container
        self.modelContainer = container
        self.feedRepo = LocalFeedRepository(modelContainer: container)
        self.articleRepo = LocalArticleRepository(modelContainer: container)
        self.settingsRepo = LocalSettingsRepository(modelContainer: container)
    }

    private func getPoller() -> FeedPoller {
        if let poller { return poller }
        let newPoller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        poller = newPoller
        return newPoller
    }

    func loadFeeds() async {
        isLoading = true
        async let loadedFeeds = feedRepo.list()
        async let loadedCounts = articleRepo.activeArticleCountsByFeed()
        async let loadedReputations = articleRepo.listFeedReputationSummaries()
        async let loadedLowestReputation = articleRepo.listLowestReputationFeeds(limit: 20)

        feeds = await loadedFeeds
        activeArticleCountsByFeed = await loadedCounts
        let reputationSummaries = await loadedReputations
        feedReputationsByFeedKey = Dictionary(uniqueKeysWithValues: reputationSummaries.map { ($0.feedKey, $0) })
        lowestReputationFeeds = await loadedLowestReputation
        isLoading = false
    }

    /// Refresh all feeds — fetches new articles from every enabled feed.
    func refreshAllFeeds() async {
        isPolling = true
        lastPollMessage = nil

        let refreshResult = await RefreshCoordinator.shared.runManualRefresh(
            modelContainer: modelContainer,
            keychainService: AppConfiguration.shared.keychainService
        )

        lastPollMessage = formatPollResult(refreshResult.result, storage: refreshResult.storage)
        if refreshResult.prepared > 0 {
            lastPollMessage = (lastPollMessage ?? "") + " · \(refreshResult.prepared) prepared"
        }
        isPolling = false

        // Reload feed list to show updated article counts + poll timestamps
        await loadFeeds()
    }

    /// Poll a single feed (e.g., right after adding it for title auto-detection).
    func pollSingleFeed(id: String) async {
        let poller = getPoller()
        let archiveAfterDays = await settingsRepo.archiveAfterDays()
        let deleteArchivedAfterDays = await settingsRepo.deleteArchivedAfterDays()
        let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()
        _ = await poller.pollFeed(id: id, archiveAfterDays: archiveAfterDays)
        _ = await poller.enforceArticleStoragePolicies(
            archiveAfterDays: archiveAfterDays,
            deleteArchivedAfterDays: deleteArchivedAfterDays,
            maxArticlesPerFeed: maxArticlesPerFeed
        )
        await loadFeeds()
    }

    func addSingleFeed(feedUrl: String, title: String) async -> String? {
        do {
            if await feedRepo.getByUrl(feedUrl) != nil {
                lastPollMessage = "Feed already exists"
                await loadFeeds()
                return nil
            }

            let feed = try await feedRepo.add(feedUrl: feedUrl, title: title)
            await pollSingleFeed(id: feed.id)
            lastPollMessage = "Added 1 feed"
            return nil
        } catch {
            return "Failed to add feed: \(error.localizedDescription)"
        }
    }

    func importOPMLFeeds(_ entries: [OPMLFeedEntry]) async -> String? {
        var addedCount = 0
        var skippedCount = 0

        do {
            for entry in entries {
                if await feedRepo.getByUrl(entry.feedURL) != nil {
                    skippedCount += 1
                    continue
                }

                _ = try await feedRepo.add(feedUrl: entry.feedURL, title: entry.title)
                addedCount += 1
            }

            await loadFeeds()

            if addedCount > 0 && skippedCount > 0 {
                lastPollMessage = "Imported \(addedCount) feed\(addedCount == 1 ? "" : "s") · \(skippedCount) duplicate\(skippedCount == 1 ? "" : "s") skipped"
            } else if addedCount > 0 {
                lastPollMessage = "Imported \(addedCount) feed\(addedCount == 1 ? "" : "s")"
            } else {
                lastPollMessage = "All imported feeds already exist"
            }

            return nil
        } catch {
            return "Failed to import feeds: \(error.localizedDescription)"
        }
    }

    func makeOPMLExportPayload() throws -> FeedOPMLExportPayload {
        let entries = feeds
            .sorted {
                let lhs = $0.title.isEmpty ? $0.feedUrl.localizedLowercase : $0.title.localizedLowercase
                let rhs = $1.title.isEmpty ? $1.feedUrl.localizedLowercase : $1.title.localizedLowercase
                return lhs < rhs
            }
            .map { feed in
                OPMLFeedEntry(
                    feedURL: feed.feedUrl,
                    title: feed.title,
                    siteURL: feed.siteUrl
                )
            }

        let data = try OPMLDocument.data(entries: entries)
        let filename = "nebular-news-feeds-\(Self.exportDateFormatter.string(from: Date())).opml"
        return FeedOPMLExportPayload(
            document: FeedOPMLDocument(data: data),
            defaultFilename: filename
        )
    }

    func deleteFeed(_ feed: Feed) async {
        do {
            try await feedRepo.delete(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
        }
    }

    func toggleEnabled(_ feed: Feed) async {
        do {
            try await feedRepo.setEnabled(id: feed.id, enabled: !feed.isEnabled)
            await loadFeeds()
        } catch {
            errorMessage = "Failed to update feed: \(error.localizedDescription)"
        }
    }

    // MARK: - Poll Result Formatting

    // TODO: User contribution opportunity — customize how poll results are displayed.
    // Consider: toast vs. subtitle, level of detail, auto-dismiss timing.
    func activeArticleCount(for feedID: String) -> Int {
        activeArticleCountsByFeed[feedID] ?? 0
    }

    func reputationSummary(for feedKey: String) -> FeedReputationSummary? {
        feedReputationsByFeedKey[feedKey]
    }

    private func formatPollResult(_ result: PollCycleResult, storage: ArticleStoragePolicyResult) -> String {
        var parts: [String] = []

        if result.newArticles > 0 {
            parts.append("\(result.newArticles) new article\(result.newArticles == 1 ? "" : "s")")
        }
        if result.errors > 0 {
            parts.append("\(result.errors) error\(result.errors == 1 ? "" : "s")")
        }
        if result.feedsSkipped > 0 {
            parts.append("\(result.feedsSkipped) skipped")
        }
        if storage.archivedByAge > 0 {
            parts.append("\(storage.archivedByAge) aged archived")
        }
        if storage.archivedByFeedLimit > 0 {
            parts.append("\(storage.archivedByFeedLimit) over limit archived")
        }
        if storage.restored > 0 {
            parts.append("\(storage.restored) restored")
        }
        if storage.deleted > 0 {
            parts.append("\(storage.deleted) archived deleted")
        }

        if parts.isEmpty {
            return "All feeds up to date"
        }
        return parts.joined(separator: " · ")
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
