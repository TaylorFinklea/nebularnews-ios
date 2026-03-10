import Foundation
import SwiftData
import NebularNewsKit

actor PersonalizationMigrationCoordinator {
    static let shared = PersonalizationMigrationCoordinator()

    func migrateIfNeeded(modelContainer: ModelContainer, keychainService: String) async {
        let service = LocalStandalonePersonalizationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )
        await service.bootstrap()
        _ = await service.rebuildPersonalizationFromHistory(batchSize: 200)
    }
}

actor RefreshCoordinator {
    static let shared = RefreshCoordinator()

    func runWarmStart(modelContainer: ModelContainer, keychainService: String) async {
        await refreshIfNeeded(
            modelContainer: modelContainer,
            keychainService: keychainService,
            allowLowPriority: false,
            bypassBackoff: false
        )
        Task(priority: .background) {
            await PersonalizationMigrationCoordinator.shared.migrateIfNeeded(
                modelContainer: modelContainer,
                keychainService: keychainService
            )
        }
    }

    func runManualRefresh(modelContainer: ModelContainer, keychainService: String) async -> (result: PollCycleResult, deleted: Int, trimmed: Int, prepared: Int) {
        await PersonalizationMigrationCoordinator.shared.migrateIfNeeded(
            modelContainer: modelContainer,
            keychainService: keychainService
        )

        let feedRepo = LocalFeedRepository(modelContainer: modelContainer)
        let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        let settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let preparation = ArticlePreparationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )

        let retentionDays = await settingsRepo.retentionDays()
        let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()

        let result = await poller.pollAllFeeds(bypassBackoff: true)
        let storage = await poller.enforceArticleStoragePolicies(
            retentionDays: retentionDays,
            maxArticlesPerFeed: maxArticlesPerFeed
        )
        let prepared = await preparation.processPendingArticles(batchSize: 10, allowLowPriority: true)
        return (result, storage.deleted, storage.trimmed, prepared)
    }

    func runBackgroundRefresh(modelContainer: ModelContainer, keychainService: String) async {
        await PersonalizationMigrationCoordinator.shared.migrateIfNeeded(
            modelContainer: modelContainer,
            keychainService: keychainService
        )
        await refreshIfNeeded(
            modelContainer: modelContainer,
            keychainService: keychainService,
            allowLowPriority: true,
            bypassBackoff: false
        )
    }

    private func refreshIfNeeded(
        modelContainer: ModelContainer,
        keychainService: String,
        allowLowPriority: Bool,
        bypassBackoff: Bool
    ) async {
        let feedRepo = LocalFeedRepository(modelContainer: modelContainer)
        let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        let settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let preparation = ArticlePreparationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )

        if await feedsAreStale(feedRepo: feedRepo, settingsRepo: settingsRepo) {
            let retentionDays = await settingsRepo.retentionDays()
            let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()
            _ = await poller.pollAllFeeds(bypassBackoff: bypassBackoff)
            _ = await poller.enforceArticleStoragePolicies(
                retentionDays: retentionDays,
                maxArticlesPerFeed: maxArticlesPerFeed
            )
        }

        _ = try? await articleRepo.backfillMissingProcessingJobsForInvisibleArticles(
            limit: allowLowPriority ? 80 : 40
        )

        _ = await preparation.processPendingArticles(
            batchSize: allowLowPriority ? 8 : 16,
            allowLowPriority: allowLowPriority
        )
    }

    private func feedsAreStale(
        feedRepo: LocalFeedRepository,
        settingsRepo: LocalSettingsRepository
    ) async -> Bool {
        let intervalMinutes = await settingsRepo.pollIntervalMinutes()
        let threshold = Date().addingTimeInterval(TimeInterval(-intervalMinutes * 60))
        let feeds = await feedRepo.listSnapshots().filter(\.isEnabled)

        guard !feeds.isEmpty else {
            return false
        }

        return feeds.contains { snapshot in
            guard let lastPolledAt = snapshot.lastPolledAt else {
                return true
            }
            return lastPolledAt < threshold
        }
    }
}

enum WarmStartCoordinator {
    static func schedule(
        modelContainer: ModelContainer,
        keychainService: String
    ) {
        Task(priority: .utility) {
            await RefreshCoordinator.shared.runWarmStart(
                modelContainer: modelContainer,
                keychainService: keychainService
            )
        }
    }
}
