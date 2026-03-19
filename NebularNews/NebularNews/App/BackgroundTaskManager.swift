import BackgroundTasks
import os
import SwiftData
import NebularNewsKit

private let logger = Logger(subsystem: "com.nebularnews", category: "BackgroundTask")

/// Manages background feed polling using the BackgroundTasks framework.
///
/// Registers a `BGAppRefreshTask` that polls feeds and cleans up old articles
/// while the app is in the background. iOS controls exact timing (minimum ~15 min).
enum BackgroundTaskManager {
    static var refreshTaskIdentifier: String {
        AppConfiguration.shared.backgroundRefreshTaskIdentifier
    }

    static var processingTaskIdentifier: String {
        AppConfiguration.shared.backgroundProcessingTaskIdentifier
    }

    /// Register the background task handler. Call once from `NebularNewsApp.init()`.
    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefreshTask(refreshTask, modelContainer: modelContainer)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleProcessingTask(processingTask, modelContainer: modelContainer)
        }
    }

    /// Schedule the next background refresh.
    static func scheduleNextRefresh(intervalMinutes: Int = 30) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalMinutes * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not critical — will retry on next app background transition
            logger.warning("Failed to schedule refresh: \(error)")
        }
    }

    static func scheduleNextProcessing(intervalMinutes: Int = 45) {
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalMinutes * 60))
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.warning("Failed to schedule processing: \(error)")
        }
    }

    /// Handle a background refresh task.
    private static func handleRefreshTask(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        // Schedule the NEXT task immediately — if iOS kills this one early,
        // at least the next refresh is already queued.
        scheduleNextRefresh()
        scheduleNextProcessing()

        let appState = AppState(configuration: AppConfiguration.shared)
        if appState.isCompanionMode && appState.hasCompanionSession {
            handleCompanionRefreshTask(task, api: appState.mobileAPI)
            return
        }

        // Create a task that iOS can cancel if time runs out
        let pollTask = Task {
            await RefreshCoordinator.shared.runBackgroundRefresh(
                modelContainer: modelContainer,
                keychainService: AppConfiguration.shared.keychainService
            )
        }

        // If iOS needs to terminate this task early
        task.expirationHandler = {
            pollTask.cancel()
        }

        // Mark task complete when polling finishes
        Task {
            _ = await pollTask.result
            task.setTaskCompleted(success: !pollTask.isCancelled)
        }
    }

    private static func handleProcessingTask(_ task: BGProcessingTask, modelContainer: ModelContainer) {
        scheduleNextProcessing()

        let processingTask = Task {
            await PersonalizationMigrationCoordinator.shared.migrateIfNeeded(
                modelContainer: modelContainer,
                keychainService: AppConfiguration.shared.keychainService
            )
            let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
            let preparation = ArticlePreparationService(
                modelContainer: modelContainer,
                keychainService: AppConfiguration.shared.keychainService
            )

            for _ in 0..<20 {
                let backfilled = (try? await articleRepo.backfillMissingImageJobsForVisibleArticles(limit: 120)) ?? 0
                let processed = await preparation.processPendingArticles(
                    batchSize: 12,
                    allowLowPriority: true
                )

                if processed == 0 && backfilled == 0 {
                    break
                }

                if Task.isCancelled {
                    break
                }
            }
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        Task {
            _ = await processingTask.result
            task.setTaskCompleted(success: !processingTask.isCancelled)
        }
    }

    // MARK: - Companion mode background refresh

    private static func handleCompanionRefreshTask(_ task: BGAppRefreshTask, api: MobileAPIClient) {
        let refreshTask = Task {
            // Trigger server poll
            _ = try? await api.triggerPull()
            try? await Task.sleep(for: .seconds(3))

            // Prefetch today + articles and cache them
            if let today = try? await api.fetchToday() {
                await CompanionCache.shared.store(today, category: .today)
            }
            if let articles = try? await api.fetchArticles() {
                await CompanionCache.shared.store(articles.articles, category: .articleList)
            }
            if let saved = try? await api.fetchSavedArticles() {
                await CompanionCache.shared.store(saved.articles, category: .savedArticles)
            }

            // Clean up stale cache entries
            await CompanionCache.shared.evictStale()
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            _ = await refreshTask.result
            task.setTaskCompleted(success: !refreshTask.isCancelled)
        }
    }
}
