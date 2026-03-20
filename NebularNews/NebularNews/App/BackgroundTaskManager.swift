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

        let appState = AppState(configuration: AppConfiguration.shared)
        guard appState.hasCompanionSession else {
            task.setTaskCompleted(success: true)
            return
        }

        let refreshTask = Task {
            let api = appState.mobileAPI
            _ = try? await api.triggerPull()
            try? await Task.sleep(for: .seconds(3))

            if let today = try? await api.fetchToday() {
                await CompanionCache.shared.store(today, category: .today)
            }
            if let articles = try? await api.fetchArticles() {
                await CompanionCache.shared.store(articles.articles, category: .articleList)
            }
            if let saved = try? await api.fetchSavedArticles() {
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
