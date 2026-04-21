import Foundation
import SwiftData
import Network
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Payload types for offline queue serialization

struct ReadPayload: Codable {
    let isRead: Bool
}

struct SavePayload: Codable {
    let saved: Bool
}

struct ReactionPayload: Codable {
    let value: Int
    let reasonCodes: [String]
}

struct TagPayload: Codable {
    let tagName: String?
    let tagId: String?
}

struct FeedSettingsPayload: Codable {
    let paused: Bool?
    let maxArticlesPerDay: Int?
    let minScore: Int?
}

struct SubscribeFeedPayload: Codable {
    let url: String
    let scrapeMode: String?
}

struct EmptyPayload: Codable {}

// MARK: - SyncManager

/// Manages offline action queuing and network connectivity monitoring.
///
/// When the device is online, mutations are sent directly to Supabase.
/// When offline (or if a request fails mid-flight), they are queued as
/// `PendingAction` rows in SwiftData and replayed in FIFO order once
/// connectivity returns.
@MainActor
@Observable
final class SyncManager {
    private let modelContext: ModelContext
    private let supabase: SupabaseManager
    private let monitor = NWPathMonitor()
    private let logger = Logger(subsystem: "com.nebularnews", category: "SyncManager")

    /// Reference back to AppState for optimistic cache updates.
    weak var appState: AppState?

    /// Whether the device currently lacks network connectivity.
    private(set) var isOffline: Bool = false

    /// Number of actions waiting to sync.
    var pendingActionCount: Int {
        fetchPendingActions().count
    }

    /// Dead-letter actions — exceeded max retries without succeeding.
    /// Surface these in Settings so the user can retry or discard manually.
    var deadLetterActionCount: Int {
        fetchDeadLetterActions().count
    }

    /// Whether any pending action targets a given resource id. Callers use this
    /// to show a "syncing" indicator next to affected rows. For feed mutations
    /// `resourceId` is the feed id; for article mutations it's the article id.
    func hasPendingAction(forResource resourceId: String) -> Bool {
        let ceiling = maxRetries
        var descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate<PendingAction> {
                $0.articleId == resourceId && $0.retryCount < ceiling
            }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    /// Max retries before a queued action moves to the dead-letter state.
    private let maxRetries = 10

    init(modelContext: ModelContext, supabase: SupabaseManager) {
        self.modelContext = modelContext
        self.supabase = supabase
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Network monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = (path.status != .satisfied)
                if wasOffline && !self.isOffline {
                    self.logger.info("Network restored — syncing pending actions")
                    await self.syncPendingActions()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.nebularnews.NetworkMonitor"))
    }

    // MARK: - Queue management

    func queueAction(type: String, articleId: String, payload: some Codable) {
        let data = try? JSONEncoder().encode(payload)
        let json = String(data: data ?? Data(), encoding: .utf8) ?? "{}"
        let action = PendingAction(actionType: type, articleId: articleId, payload: json)
        modelContext.insert(action)
        save()
    }

    func syncPendingActions() async {
        let pending = fetchPendingActions()
        guard !pending.isEmpty else { return }
        logger.info("Syncing \(pending.count) pending actions")

        var anySucceeded = false
        for action in pending {
            do {
                try await executeAction(action)
                modelContext.delete(action)
                anySucceeded = true
            } catch {
                action.retryCount += 1
                action.lastError = error.localizedDescription
                logger.warning("Action \(action.actionType) for \(action.articleId) failed (attempt \(action.retryCount)): \(error.localizedDescription)")
                if action.retryCount >= maxRetries {
                    // Move to dead-letter state — keep the row but mark it so it
                    // stops being picked up by `fetchPendingActions`. The user
                    // can retry or discard via Settings.
                    logger.error("Dead-lettering action \(action.actionType) for \(action.articleId) after \(self.maxRetries) retries")
                }
            }
        }
        save()

        if anySucceeded {
            // Any queue flush that made at least one change could affect widget
            // state (unread count, saved count, top article). Reload timelines.
            reloadWidgetTimelines()
        }
    }

    /// Pending = retryCount < maxRetries. Dead-letter actions are excluded.
    func fetchPendingActions() -> [PendingAction] {
        let ceiling = maxRetries
        var descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate<PendingAction> { $0.retryCount < ceiling },
            sortBy: [SortDescriptor(\PendingAction.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 100
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Dead-letter = exceeded maxRetries. User visible in Advanced settings.
    func fetchDeadLetterActions() -> [PendingAction] {
        let ceiling = maxRetries
        var descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate<PendingAction> { $0.retryCount >= ceiling },
            sortBy: [SortDescriptor(\PendingAction.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 100
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Reset a dead-letter action's retry count so it gets picked up next sync.
    func retryDeadLetter(_ action: PendingAction) {
        action.retryCount = 0
        action.lastError = nil
        save()
    }

    /// Permanently discard a dead-letter action.
    func discardDeadLetter(_ action: PendingAction) {
        modelContext.delete(action)
        save()
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit) && !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    // MARK: - Action execution

    private func executeAction(_ action: PendingAction) async throws {
        switch action.actionType {
        case "read":
            let payload = try JSONDecoder().decode(ReadPayload.self, from: Data(action.payload.utf8))
            try await supabase.setRead(articleId: action.articleId, isRead: payload.isRead)
        case "save":
            let payload = try JSONDecoder().decode(SavePayload.self, from: Data(action.payload.utf8))
            _ = try await supabase.saveArticle(id: action.articleId, saved: payload.saved)
        case "reaction":
            let payload = try JSONDecoder().decode(ReactionPayload.self, from: Data(action.payload.utf8))
            _ = try await supabase.setReaction(articleId: action.articleId, value: payload.value, reasonCodes: payload.reasonCodes)
        case "tag_add":
            let payload = try JSONDecoder().decode(TagPayload.self, from: Data(action.payload.utf8))
            if let name = payload.tagName {
                _ = try await supabase.addTag(articleId: action.articleId, name: name)
            }
        case "tag_remove":
            let payload = try JSONDecoder().decode(TagPayload.self, from: Data(action.payload.utf8))
            if let tagId = payload.tagId {
                _ = try await supabase.removeTag(articleId: action.articleId, tagId: tagId)
            }
        case "feed_settings":
            // articleId holds the feed_id for feed-scoped mutations.
            let payload = try JSONDecoder().decode(FeedSettingsPayload.self, from: Data(action.payload.utf8))
            try await supabase.updateFeedSettings(
                feedId: action.articleId,
                paused: payload.paused,
                maxArticlesPerDay: payload.maxArticlesPerDay,
                minScore: payload.minScore
            )
        case "subscribe_feed":
            let payload = try JSONDecoder().decode(SubscribeFeedPayload.self, from: Data(action.payload.utf8))
            _ = try await supabase.addFeed(url: payload.url, scrapeMode: payload.scrapeMode)
        case "unsubscribe_feed":
            try await supabase.deleteFeed(id: action.articleId)
        default:
            logger.warning("Unknown action type: \(action.actionType)")
        }
    }

    // MARK: - Convenience methods (try online first, queue on failure)

    func setRead(articleId: String, isRead: Bool) async {
        // Always update cache immediately (optimistic)
        appState?.articleCache?.updateArticle(id: articleId, isRead: isRead, saved: nil, reactionValue: nil)

        if isOffline {
            queueAction(type: "read", articleId: articleId, payload: ReadPayload(isRead: isRead))
        } else {
            do {
                try await supabase.setRead(articleId: articleId, isRead: isRead)
            } catch {
                queueAction(type: "read", articleId: articleId, payload: ReadPayload(isRead: isRead))
            }
        }
    }

    func saveArticle(articleId: String, saved: Bool) async -> SaveResponse? {
        // Optimistic cache update
        appState?.articleCache?.updateArticle(id: articleId, isRead: nil, saved: saved, reactionValue: nil)

        if isOffline {
            queueAction(type: "save", articleId: articleId, payload: SavePayload(saved: saved))
            return SaveResponse(articleId: articleId, saved: saved, savedAt: saved ? Date().ISO8601Format() : nil)
        } else {
            do {
                return try await supabase.saveArticle(id: articleId, saved: saved)
            } catch {
                queueAction(type: "save", articleId: articleId, payload: SavePayload(saved: saved))
                return SaveResponse(articleId: articleId, saved: saved, savedAt: saved ? Date().ISO8601Format() : nil)
            }
        }
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async -> ReactionResponse? {
        // Optimistic cache update
        appState?.articleCache?.updateArticle(id: articleId, isRead: nil, saved: nil, reactionValue: value)

        if isOffline {
            queueAction(type: "reaction", articleId: articleId, payload: ReactionPayload(value: value, reasonCodes: reasonCodes))
            return ReactionResponse(articleId: articleId, value: value, createdAt: nil, reasonCodes: reasonCodes)
        } else {
            do {
                return try await supabase.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes)
            } catch {
                queueAction(type: "reaction", articleId: articleId, payload: ReactionPayload(value: value, reasonCodes: reasonCodes))
                return ReactionResponse(articleId: articleId, value: value, createdAt: nil, reasonCodes: reasonCodes)
            }
        }
    }

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        if isOffline {
            queueAction(type: "tag_add", articleId: articleId, payload: TagPayload(tagName: name, tagId: nil))
            throw SyncManagerError.queuedOffline
        } else {
            do {
                return try await supabase.addTag(articleId: articleId, name: name)
            } catch {
                queueAction(type: "tag_add", articleId: articleId, payload: TagPayload(tagName: name, tagId: nil))
                throw error
            }
        }
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        if isOffline {
            queueAction(type: "tag_remove", articleId: articleId, payload: TagPayload(tagName: nil, tagId: tagId))
            throw SyncManagerError.queuedOffline
        } else {
            do {
                return try await supabase.removeTag(articleId: articleId, tagId: tagId)
            } catch {
                queueAction(type: "tag_remove", articleId: articleId, payload: TagPayload(tagName: nil, tagId: tagId))
                throw error
            }
        }
    }

    // MARK: - Feed mutations (queue-aware)

    /// Update feed settings (paused, cap, min score). Queues on offline/failure.
    func updateFeedSettings(feedId: String, paused: Bool? = nil, maxArticlesPerDay: Int? = nil, minScore: Int? = nil) async throws {
        let payload = FeedSettingsPayload(paused: paused, maxArticlesPerDay: maxArticlesPerDay, minScore: minScore)
        if isOffline {
            queueAction(type: "feed_settings", articleId: feedId, payload: payload)
            throw SyncManagerError.queuedOffline
        }
        do {
            try await supabase.updateFeedSettings(feedId: feedId, paused: paused, maxArticlesPerDay: maxArticlesPerDay, minScore: minScore)
        } catch {
            queueAction(type: "feed_settings", articleId: feedId, payload: payload)
            throw error
        }
    }

    /// Subscribe to a new feed by URL. Queues on offline/failure.
    /// Returns the feed id from the backend response, or throws `queuedOffline`
    /// if the request was queued (caller may choose to optimistically reflect
    /// the subscription in UI and reconcile later).
    func subscribeFeed(url: String, scrapeMode: String? = nil) async throws -> String {
        let payload = SubscribeFeedPayload(url: url, scrapeMode: scrapeMode)
        if isOffline {
            // articleId is unused for subscribe; store the URL as a stable key
            // so dead-letter UI can still identify the target.
            queueAction(type: "subscribe_feed", articleId: url, payload: payload)
            throw SyncManagerError.queuedOffline
        }
        do {
            return try await supabase.addFeed(url: url, scrapeMode: scrapeMode)
        } catch {
            queueAction(type: "subscribe_feed", articleId: url, payload: payload)
            throw error
        }
    }

    /// Unsubscribe (delete) a feed by id. Queues on offline/failure.
    func unsubscribeFeed(feedId: String) async throws {
        if isOffline {
            queueAction(type: "unsubscribe_feed", articleId: feedId, payload: EmptyPayload())
            throw SyncManagerError.queuedOffline
        }
        do {
            try await supabase.deleteFeed(id: feedId)
        } catch {
            queueAction(type: "unsubscribe_feed", articleId: feedId, payload: EmptyPayload())
            throw error
        }
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save model context: \(error, privacy: .public)")
        }
    }
}

// MARK: - Errors

enum SyncManagerError: LocalizedError {
    case queuedOffline

    var errorDescription: String? {
        switch self {
        case .queuedOffline:
            return "Action queued — will sync when back online."
        }
    }
}
