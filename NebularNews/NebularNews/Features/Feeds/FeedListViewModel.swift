import Foundation
import Observation
import SwiftData
import NebularNewsKit

@Observable
@MainActor
final class FeedListViewModel {
    // Internal access so FeedListView can call feedRepo.add() from AddFeedSheet
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

        lastPollMessage = formatPollResult(result, deleted: deleted)
        isPolling = false

        // Reload feed list to show updated article counts + poll timestamps
        await loadFeeds()

        // Trigger AI enrichment for new articles (non-blocking for feed list refresh)
        if result.newArticles > 0 {
            await enrichNewArticles()
        }
    }

    /// Enrich unprocessed articles with AI-generated scores, summaries, and key points.
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
            userProfile: settings?.userProfilePrompt,
            scoringModel: settings?.scoringModel ?? "claude-haiku-4-5-20251001",
            summaryModel: settings?.defaultModel ?? "claude-haiku-4-5-20251001",
            summaryStyle: settings?.summaryStyle ?? "concise"
        )
        isEnriching = false

        let enriched = results.filter { $0.succeeded }.count
        if enriched > 0 {
            lastPollMessage = (lastPollMessage ?? "") + " · \(enriched) AI-enriched"
        }
    }

    /// Poll a single feed (e.g., right after adding it for title auto-detection).
    func pollSingleFeed(id: String) async {
        let poller = getPoller()
        _ = await poller.pollFeed(id: id)
        await loadFeeds()
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
