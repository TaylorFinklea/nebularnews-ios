import Foundation
import SwiftData
import os
import NebularNewsKit
#if canImport(UIKit)
import UIKit
#endif

actor ProcessingQueueSupervisor {
    static let shared = ProcessingQueueSupervisor()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
        category: "ProcessingQueue"
    )

    private let visibilityBackfillLimit = 200
    private let visibilityBatchSize = 16
    private let visibilityPassDelay = Duration.milliseconds(200)
    private let visibilityNoProgressLimit = 3
    private let lowPriorityImageBackfillLimit = 120
    private let lowPriorityBatchSize = 12
    private let lowPriorityPassDelay = Duration.milliseconds(250)
    private let watchdogInterval = Duration.seconds(30)
    private let watchdogIdleInterval = Duration.seconds(60)
    private let watchdogIdleThreshold = 3
    private let stalledQueueWarningInterval: TimeInterval = 30
    private let kickDebounce = Duration.milliseconds(250)

    private var modelContainer: ModelContainer?
    private var keychainService: String?
    private var sceneIsActive = false

    private var queueObserverTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var kickTask: Task<Void, Never>?
    private var visibilityTask: Task<Void, Never>?
    private var lowPriorityTask: Task<Void, Never>?

    private var cachedArticleRepo: LocalArticleRepository?
    private var watchdogIdle = false
    private var wantsLowPriorityDrain = false
    private var lastKickReason = "initial"
    private var lastSuccessfulDrainAt: Date?
    private var stalledSince: Date?

#if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    func activate(
        modelContainer: ModelContainer,
        keychainService: String
    ) async {
        self.modelContainer = modelContainer
        self.keychainService = keychainService
        self.cachedArticleRepo = LocalArticleRepository(modelContainer: modelContainer)
        sceneIsActive = true
        watchdogIdle = false

        await endBackgroundTaskIfNeeded()
        startQueueObserverIfNeeded()
        startWatchdogIfNeeded()
        await kick(reason: "scene_active", allowLowPriority: true)
    }

    func deactivate() async {
        sceneIsActive = false
        kickTask?.cancel()
        kickTask = nil
        lowPriorityTask?.cancel()
        lowPriorityTask = nil
        queueObserverTask?.cancel()
        queueObserverTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        wantsLowPriorityDrain = false
        cachedArticleRepo = nil

        await extendVisibilityBurstIntoBackgroundIfNeeded()
    }

    func kick(
        reason: String,
        allowLowPriority: Bool = false
    ) async {
        lastKickReason = reason
        watchdogIdle = false
        wantsLowPriorityDrain = wantsLowPriorityDrain || allowLowPriority
        logger.debug("Queue kick requested: \(reason, privacy: .public), lowPriority=\(allowLowPriority)")

        guard sceneIsActive else { return }

        kickTask?.cancel()
        kickTask = Task(priority: .utility) { [kickDebounce] in
            try? await Task.sleep(for: kickDebounce)
            await self.runKickIfNeeded()
        }
    }

    private func runKickIfNeeded() async {
        kickTask = nil
        guard sceneIsActive,
              keychainService != nil,
              let articleRepo = cachedArticleRepo
        else {
            return
        }

        let health = await articleRepo.processingQueueHealth()

        if health.pendingVisibleCount > 0 {
            startVisibilityTaskIfNeeded()
            return
        }

        if wantsLowPriorityDrain {
            startLowPriorityTaskIfNeeded()
        }
    }

    private func startQueueObserverIfNeeded() {
        guard queueObserverTask == nil else { return }

        queueObserverTask = Task(priority: .utility) {
            for await _ in NotificationCenter.default.notifications(named: ArticleChangeBus.processingQueueChanged) {
                await self.kick(reason: "queue_change", allowLowPriority: true)
            }
        }
    }

    private func startWatchdogIfNeeded() {
        guard watchdogTask == nil else { return }

        watchdogTask = Task(priority: .background) {
            var emptyChecks = 0
            while !Task.isCancelled {
                let interval = emptyChecks >= self.watchdogIdleThreshold
                    ? self.watchdogIdleInterval
                    : self.watchdogInterval
                try? await Task.sleep(for: interval)
                let hadWork = await self.evaluateQueueHealth()
                emptyChecks = hadWork ? 0 : emptyChecks + 1
            }
        }
    }

    private func startVisibilityTaskIfNeeded() {
        guard visibilityTask == nil else { return }

        visibilityTask = Task(priority: .utility) {
            await self.runVisibilityDrainLoop()
        }
    }

    private func startLowPriorityTaskIfNeeded() {
        guard lowPriorityTask == nil else { return }
        guard visibilityTask == nil else { return }

        lowPriorityTask = Task(priority: .background) {
            await self.runLowPriorityDrainLoop()
        }
    }

    private func runVisibilityDrainLoop() async {
        guard let modelContainer, let keychainService else {
            visibilityTask = nil
            return
        }

        let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        let preparation = ArticlePreparationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )

        var noProgressPasses = 0

        while sceneIsActive {
            let before = await articleRepo.processingQueueHealth()
            let backfilled = (try? await articleRepo.backfillMissingProcessingJobsForInvisibleArticles(
                limit: visibilityBackfillLimit
            )) ?? 0
            let processed = await preparation.processPendingArticles(
                batchSize: visibilityBatchSize,
                allowLowPriority: false
            )
            let after = await articleRepo.processingQueueHealth()

            let madeProgress = backfilled > 0 || processed > 0 || after.pendingVisibleCount < before.pendingVisibleCount
            if madeProgress {
                noProgressPasses = 0
                lastSuccessfulDrainAt = Date()
                stalledSince = nil
                logger.info(
                    "Visibility drain progress: pending=\(after.pendingVisibleCount), processed=\(processed), backfilled=\(backfilled), queued=\(after.queuedScoreJobCount), running=\(after.runningScoreJobCount)"
                )
            } else {
                noProgressPasses += 1
            }

            if after.pendingVisibleCount == 0 || noProgressPasses >= visibilityNoProgressLimit {
                break
            }

            try? await Task.sleep(for: visibilityPassDelay)
        }

        visibilityTask = nil
        await endBackgroundTaskIfNeeded()

        guard sceneIsActive, let repoAfterVisibility = cachedArticleRepo else { return }
        let health = await repoAfterVisibility.processingQueueHealth()

        if health.pendingVisibleCount > 0 {
            logger.notice(
                "Visibility drain stopped with pending work remaining: pending=\(health.pendingVisibleCount), queued=\(health.queuedScoreJobCount), running=\(health.runningScoreJobCount), lastKick=\(self.lastKickReason, privacy: .public)"
            )
            await kick(reason: "visibility_followup", allowLowPriority: false)
            return
        }

        if wantsLowPriorityDrain {
            startLowPriorityTaskIfNeeded()
        }
    }

    private func runLowPriorityDrainLoop() async {
        guard let modelContainer, let keychainService else {
            lowPriorityTask = nil
            return
        }

        let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        let preparation = ArticlePreparationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )

        while sceneIsActive {
            let health = await articleRepo.processingQueueHealth()
            if health.pendingVisibleCount > 0 {
                break
            }

            let backfilled = (try? await articleRepo.backfillMissingImageJobsForVisibleArticles(
                limit: lowPriorityImageBackfillLimit
            )) ?? 0
            let processed = await preparation.processPendingArticles(
                batchSize: lowPriorityBatchSize,
                allowLowPriority: true
            )

            if processed == 0 && backfilled == 0 {
                break
            }

            logger.debug("Low-priority drain progress: processed=\(processed), imageBackfilled=\(backfilled)")
            try? await Task.sleep(for: lowPriorityPassDelay)
        }

        lowPriorityTask = nil
        wantsLowPriorityDrain = false

        guard sceneIsActive, let repoAfterLowPriority = cachedArticleRepo else { return }
        let healthAfterLowPriority = await repoAfterLowPriority.processingQueueHealth()
        if healthAfterLowPriority.pendingVisibleCount > 0 {
            await kick(reason: "low_priority_preempted", allowLowPriority: false)
        }
    }

    @discardableResult
    private func evaluateQueueHealth() async -> Bool {
        guard sceneIsActive, !watchdogIdle, let articleRepo = cachedArticleRepo else { return false }

        let health = await articleRepo.processingQueueHealth()

        guard health.pendingVisibleCount > 0 else {
            stalledSince = nil
            watchdogIdle = true
            return false
        }

        guard health.runningScoreJobCount == 0 else {
            stalledSince = nil
            return true
        }

        let now = Date()
        if let stalledSince {
            let stalledDuration = now.timeIntervalSince(stalledSince)
            if stalledDuration >= stalledQueueWarningInterval {
                logger.warning(
                    "Visibility queue idle while pending work remains for \(stalledDuration, privacy: .public)s: pending=\(health.pendingVisibleCount), queued=\(health.queuedScoreJobCount), lastKick=\(self.lastKickReason, privacy: .public), lastSuccess=\(self.lastSuccessfulDrainAt?.formatted() ?? "never", privacy: .public)"
                )
            } else {
                logger.notice(
                    "Visibility queue idle with pending work: pending=\(health.pendingVisibleCount), queued=\(health.queuedScoreJobCount), lastKick=\(self.lastKickReason, privacy: .public)"
                )
            }
        } else {
            stalledSince = now
            logger.notice(
                "Visibility queue entered idle state: pending=\(health.pendingVisibleCount), queued=\(health.queuedScoreJobCount), lastKick=\(self.lastKickReason, privacy: .public)"
            )
        }

        await kick(reason: "idle_watchdog", allowLowPriority: false)
        return true
    }

    private func extendVisibilityBurstIntoBackgroundIfNeeded() async {
        guard visibilityTask != nil else { return }

#if canImport(UIKit)
        guard backgroundTaskID == .invalid else { return }

        let taskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "NebularVisibilityDrain") {
                Task {
                    await ProcessingQueueSupervisor.shared.handleBackgroundTaskExpiration()
                }
            }
        }

        guard taskID != .invalid else { return }

        backgroundTaskID = taskID
        logger.info("Extending visibility drain into background")

        let activeTask = visibilityTask
        Task(priority: .background) {
            _ = await activeTask?.result
            await ProcessingQueueSupervisor.shared.endBackgroundTaskIfNeeded()
        }
#endif
    }

    private func handleBackgroundTaskExpiration() async {
        logger.warning("Background time expired while draining visibility queue")
        await endBackgroundTaskIfNeeded()
    }

    private func endBackgroundTaskIfNeeded() async {
#if canImport(UIKit)
        guard backgroundTaskID != .invalid else { return }
        let taskID = backgroundTaskID
        backgroundTaskID = .invalid
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(taskID)
        }
#endif
    }
}
