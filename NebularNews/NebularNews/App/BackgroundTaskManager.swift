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

    /// Register the background task handler. Call once from `NebularNewsApp.init()`.
    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefreshTask(refreshTask, modelContainer: modelContainer)
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

    /// Handle a background refresh task.
    private static func handleRefreshTask(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        // Schedule the NEXT task immediately — if iOS kills this one early,
        // at least the next refresh is already queued.
        scheduleNextRefresh()

        let feedRepo = LocalFeedRepository(modelContainer: modelContainer)
        let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)

        // Create a task that iOS can cancel if time runs out
        let pollTask = Task {
            // Automatic poll respects backoff (not user-initiated)
            _ = await poller.pollAllFeeds(bypassBackoff: false)
            _ = await poller.cleanupOldArticles(retentionDays: 90)
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
}
