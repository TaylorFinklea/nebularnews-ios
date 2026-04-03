#if os(iOS)
import BackgroundTasks
import os
import SwiftData

private let logger = Logger(subsystem: "com.nebularnews", category: "BackgroundTask")

enum BackgroundTaskManager {
    static var refreshTaskIdentifier: String {
        AppConfiguration.shared.backgroundRefreshTaskIdentifier
    }

    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefreshTask(refreshTask)
        }
    }

    static func scheduleNextRefresh(intervalMinutes: Int = 30) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalMinutes * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.warning("Failed to schedule refresh: \(error)")
        }
    }

    private static func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let supabase = SupabaseManager.shared

        let refreshTask = Task {
            // Check if we have an active session
            guard let _ = try? await supabase.session() else {
                return
            }

            try? await supabase.triggerPull()
            try? await Task.sleep(for: .seconds(3))

            if let today = try? await supabase.fetchToday() {
                await CompanionCache.shared.store(today, category: .today)

                // Update Home Screen widgets with fresh data
                WidgetDataWriter.updateFromToday(
                    stats: today.stats,
                    hero: today.hero,
                    upNext: today.upNext
                )
            }
            if let articles = try? await supabase.fetchArticles() {
                await CompanionCache.shared.store(articles.articles, category: .articleList)
            }
            if let saved = try? await supabase.fetchArticles(saved: true) {
                await CompanionCache.shared.store(saved.articles, category: .savedArticles)
            }

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
#else
import SwiftData

/// Stub for macOS where BGTaskScheduler is not available.
enum BackgroundTaskManager {
    static func register(modelContainer: ModelContainer) {}
    static func scheduleNextRefresh(intervalMinutes: Int = 30) {}
}
#endif
