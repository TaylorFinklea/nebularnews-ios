import Foundation
import Observation
import SwiftData
import NebularNewsKit

@Observable
@MainActor
final class FeedListViewModel {
    let feedRepo: LocalFeedRepository
    private let articleRepo: LocalArticleRepository
    private let settingsRepo: LocalSettingsRepository
    private let modelContainer: ModelContainer
    private var poller: FeedPoller?

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
        feeds = await feedRepo.list()
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

        lastPollMessage = formatPollResult(
            refreshResult.result,
            deleted: refreshResult.deleted,
            trimmed: refreshResult.trimmed
        )
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
        let retentionDays = await settingsRepo.retentionDays()
        let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()
        _ = await poller.pollFeed(id: id)
        _ = await poller.enforceArticleStoragePolicies(
            retentionDays: retentionDays,
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
    private func formatPollResult(_ result: PollCycleResult, deleted: Int, trimmed: Int) -> String {
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
        if deleted > 0 {
            parts.append("\(deleted) old removed")
        }
        if trimmed > 0 {
            parts.append("\(trimmed) over limit removed")
        }

        if parts.isEmpty {
            return "All feeds up to date"
        }
        return parts.joined(separator: " · ")
    }
}
