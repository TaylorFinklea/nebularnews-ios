import Foundation
import Observation
import SwiftData
import NebularNewsKit

@Observable
@MainActor
final class FeedListViewModel {
    let feedRepo: LocalFeedRepository
    private let articleRepo: LocalArticleRepository
    private let modelContainer: ModelContainer
    private var poller: FeedPoller?

    var feeds: [Feed] = []
    var isLoading = false
    var isPolling = false
    var isEnriching = false
    var showAddSheet = false
    var errorMessage: String?
    var lastPollMessage: String?

    init(modelContext: ModelContext) {
        let container = modelContext.container
        self.modelContainer = container
        self.feedRepo = LocalFeedRepository(modelContainer: container)
        self.articleRepo = LocalArticleRepository(modelContainer: container)
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

        let poller = getPoller()
        let result = await poller.pollAllFeeds(bypassBackoff: true)

        // Cleanup old articles (default 90 days)
        let deleted = await poller.cleanupOldArticles(retentionDays: 90)

        let processed = await processStandalonePersonalization()

        lastPollMessage = formatPollResult(result, deleted: deleted)
        if processed > 0 {
            lastPollMessage = (lastPollMessage ?? "") + " · \(processed) scored"
        }
        isPolling = false

        // Reload feed list to show updated article counts + poll timestamps
        await loadFeeds()

        // Trigger optional AI enrichment for summary + key points.
        await enrichNewArticles()
    }

    /// Enrich unprocessed articles with optional AI summaries and key points.
    func enrichNewArticles() async {
        let keychain = KeychainManager()
        guard let apiKey = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) else { return }

        isEnriching = true
        let client = AnthropicClient(apiKey: apiKey)
        let enricher = AIEnrichmentService(client: client, articleRepo: articleRepo)
        let settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
        let settings = await settingsRepo.get()
        let results = await enricher.enrichUnprocessedArticles(
            limit: 5,
            summaryModel: settings?.defaultModel ?? "claude-haiku-4-5-20251001",
            summaryStyle: settings?.summaryStyle ?? "concise"
        )
        isEnriching = false

        let enriched = results.filter { $0.succeeded }.count
        if enriched > 0 {
            lastPollMessage = (lastPollMessage ?? "") + " · \(enriched) AI-enriched"
        }
    }

    private func processStandalonePersonalization() async -> Int {
        let service = LocalStandalonePersonalizationService(modelContainer: modelContainer)
        return await service.processPendingArticles(limit: 50)
    }

    /// Poll a single feed (e.g., right after adding it for title auto-detection).
    func pollSingleFeed(id: String) async {
        let poller = getPoller()
        _ = await poller.pollFeed(id: id)
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
    private func formatPollResult(_ result: PollCycleResult, deleted: Int) -> String {
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

        if parts.isEmpty {
            return "All feeds up to date"
        }
        return parts.joined(separator: " · ")
    }
}
