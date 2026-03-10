import BackgroundTasks
import SwiftData
import NebularNewsKit

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
            print("[BackgroundTaskManager] Failed to schedule: \(error)")
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
            print("[BackgroundTaskManager] Failed to schedule processing: \(error)")
        }
    }

    /// Handle a background refresh task.
    private static func handleRefreshTask(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        // Schedule the NEXT task immediately — if iOS kills this one early,
        // at least the next refresh is already queued.
        scheduleNextRefresh()
        scheduleNextProcessing()

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
}
