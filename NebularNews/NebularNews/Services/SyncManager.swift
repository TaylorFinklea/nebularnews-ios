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

struct ReadingPositionPayload: Codable {
    let percent: Int
}

struct FeedSettingsPayload: Codable {
    let paused: Bool?
    let maxArticlesPerDay: Int?
    let minScore: Int?
    /// ETag captured when the save sheet was opened.
    /// Sent as `If-Match` on execution. Old queued payloads decode with nil
    /// and behave like a non–If-Match save (last-writer-wins, no 412 guard).
    let ifMatch: String?
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
            } catch SyncManagerError.parkedAsConflict {
                // Action was parked as a conflict — state and snapshot already
                // written inside executeAction. Skip retryCount bump and delete.
                continue
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

    /// Pending = state is "pending" AND retryCount < maxRetries.
    /// Conflict-parked and dead-letter actions are excluded.
    func fetchPendingActions() -> [PendingAction] {
        let ceiling = maxRetries
        var descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate<PendingAction> { $0.state == "pending" && $0.retryCount < ceiling },
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

    /// Conflicted actions — parked for user resolution.
    /// The inspector agent and the conflict sheet use this to enumerate pending conflicts.
    func fetchConflictedActions() -> [PendingAction] {
        var descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate<PendingAction> { $0.state == "conflict" },
            sortBy: [SortDescriptor(\PendingAction.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 100
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Number of actions currently parked in conflict state.
    var conflictedActionCount: Int {
        fetchConflictedActions().count
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
            do {
                _ = try await supabase.updateFeedSettings(
                    feedId: action.articleId,
                    paused: payload.paused,
                    maxArticlesPerDay: payload.maxArticlesPerDay,
                    minScore: payload.minScore,
                    ifMatch: payload.ifMatch
                )
            } catch let APIError.preconditionFailed(currentEtag, _) {
                // Park the action — do NOT bump retryCount, do NOT delete.
                action.state = "conflict"
                action.conflictServerEtag = currentEtag
                // Server only returns the etag on 412, not the current values.
                // Best-effort: re-fetch the feed list and snapshot the matching row.
                if let snap = await fetchFeedSnapshotJSON(feedId: action.articleId) {
                    action.conflictServerSnapshotJSON = snap
                }
                logger.warning("412 conflict on feed_settings for \(action.articleId) — parked for user resolution")
                appState?.feedConflicts.notify(feedId: action.articleId)
                save()
                // Throw a sentinel so the outer loop skips delete and retryCount bump.
                throw SyncManagerError.parkedAsConflict
            } catch let APIError.serverError(statusCode, _) where statusCode == 404 {
                // Feed subscription was deleted before this conflict was resolved.
                // Drop the action silently — no subscription means nothing to PATCH.
                logger.debug("feed_settings action for \(action.articleId) got 404 (subscription deleted) — discarding")
                // Clean up any pending conflict notification for this feed.
                appState?.feedConflicts.resolved(feedId: action.articleId)
                // Re-throw so the outer loop's catch branch picks it up, but it will
                // still increment retryCount. To avoid that we use the parkedAsConflict
                // sentinel: the outer loop skips retryCount and delete, then we clean up
                // the action via a second delete call. SwiftData ignores double-deletes.
                modelContext.delete(action)
                save()
                throw SyncManagerError.parkedAsConflict
            }
        case "subscribe_feed":
            let payload = try JSONDecoder().decode(SubscribeFeedPayload.self, from: Data(action.payload.utf8))
            _ = try await supabase.addFeed(url: payload.url, scrapeMode: payload.scrapeMode)
        case "unsubscribe_feed":
            try await supabase.deleteFeed(id: action.articleId)
        case "reading_position":
            let payload = try JSONDecoder().decode(ReadingPositionPayload.self, from: Data(action.payload.utf8))
            try await supabase.updateReadingPosition(articleId: action.articleId, percent: payload.percent)
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
                reloadWidgetTimelines()
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
                let result = try await supabase.saveArticle(id: articleId, saved: saved)
                reloadWidgetTimelines()
                return result
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
                let result = try await supabase.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes)
                reloadWidgetTimelines()
                return result
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
    ///
    /// `ifMatch` is the ETag computed when the save sheet was opened. When
    /// provided the PATCH includes `If-Match`; a stale etag causes a 412 which
    /// the caller receives as `APIError.preconditionFailed`.
    func updateFeedSettings(
        feedId: String,
        paused: Bool? = nil,
        maxArticlesPerDay: Int? = nil,
        minScore: Int? = nil,
        ifMatch: String? = nil
    ) async throws {
        let payload = FeedSettingsPayload(
            paused: paused,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore,
            ifMatch: ifMatch
        )
        if isOffline {
            queueAction(type: "feed_settings", articleId: feedId, payload: payload)
            throw SyncManagerError.queuedOffline
        }
        do {
            _ = try await supabase.updateFeedSettings(
                feedId: feedId,
                paused: paused,
                maxArticlesPerDay: maxArticlesPerDay,
                minScore: minScore,
                ifMatch: ifMatch
            )
        } catch {
            queueAction(type: "feed_settings", articleId: feedId, payload: payload)
            throw error
        }
    }

    /// Queue a feed_settings action that is already in the conflict state.
    ///
    /// Called from the live-save path in `FeedSettingsSheet` when a direct
    /// PATCH returns 412 (the mutation bypassed the queue). This mirrors the
    /// park-and-notify logic in `executeAction` for queued 412s.
    func queueConflict(
        feedId: String,
        paused: Bool?,
        maxArticlesPerDay: Int?,
        minScore: Int?,
        ifMatch: String?,
        serverEtag: String
    ) {
        let payload = FeedSettingsPayload(
            paused: paused,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore,
            ifMatch: ifMatch
        )
        let data = try? JSONEncoder().encode(payload)
        let json = String(data: data ?? Data(), encoding: .utf8) ?? "{}"
        let action = PendingAction(actionType: "feed_settings", articleId: feedId, payload: json)
        action.state = "conflict"
        action.ifMatchEtag = ifMatch
        action.conflictServerEtag = serverEtag
        modelContext.insert(action)

        // Best-effort snapshot (fire and forget)
        Task {
            if let snap = await fetchFeedSnapshotJSON(feedId: feedId) {
                action.conflictServerSnapshotJSON = snap
                save()
            }
        }

        save()
        appState?.feedConflicts.notify(feedId: feedId)
        logger.warning("412 conflict on feed_settings for \(feedId) (live-save path) — parked for user resolution")
    }

    /// Resolve a parked conflict action with the user's chosen resolution.
    ///
    /// Rewrites the payload with merged values, sets `If-Match` to the server's
    /// etag (the value the user saw in the diff sheet), resets `state` to
    /// "pending" and `retryCount` to 0, then immediately syncs the queue so the
    /// user sees the change land.
    func resolveConflict(_ action: PendingAction, with resolution: FeedSettingsResolution) {
        guard action.state == "conflict", action.actionType == "feed_settings" else {
            logger.warning("resolveConflict called on non-conflict action \(action.id)")
            return
        }

        // Decode existing payload to get the local ("mine") values.
        guard let existing = try? JSONDecoder().decode(
            FeedSettingsPayload.self,
            from: Data(action.payload.utf8)
        ) else {
            logger.error("resolveConflict: failed to decode payload for action \(action.id)")
            return
        }

        // Decode the server snapshot to get server values.
        let serverSnap: FeedSettingsPayload? = {
            guard let json = action.conflictServerSnapshotJSON else { return nil }
            return try? JSONDecoder().decode(FeedSettingsPayload.self, from: Data(json.utf8))
        }()

        // Merge: for each field pick server or mine per the resolution.
        let resolvedPaused: Bool? = {
            switch resolution.paused {
            case .server: return serverSnap?.paused ?? existing.paused
            case .mine: return existing.paused
            }
        }()
        let resolvedMax: Int? = {
            switch resolution.maxArticlesPerDay {
            case .server: return serverSnap?.maxArticlesPerDay ?? existing.maxArticlesPerDay
            case .mine: return existing.maxArticlesPerDay
            }
        }()
        let resolvedMin: Int? = {
            switch resolution.minScore {
            case .server: return serverSnap?.minScore ?? existing.minScore
            case .mine: return existing.minScore
            }
        }()

        // The resolved payload sends the server's etag as If-Match — we've now
        // acknowledged the server state so the next PATCH uses that as the
        // optimistic concurrency token.
        let newPayload = FeedSettingsPayload(
            paused: resolvedPaused,
            maxArticlesPerDay: resolvedMax,
            minScore: resolvedMin,
            ifMatch: action.conflictServerEtag
        )

        if let data = try? JSONEncoder().encode(newPayload),
           let json = String(data: data, encoding: .utf8) {
            action.payload = json
        }

        action.state = "pending"
        action.retryCount = 0
        action.lastError = nil
        action.conflictServerEtag = nil
        action.conflictServerSnapshotJSON = nil

        save()
        appState?.feedConflicts.resolved(feedId: action.articleId)

        // Kick off a sync immediately so the user sees the result.
        Task { await syncPendingActions() }
    }

    /// Best-effort snapshot of a feed's current server state as a JSON string.
    ///
    /// Re-fetches the feed list and JSON-encodes the matching row as a
    /// `FeedSettingsPayload`. Returns nil on any failure — the conflict sheet
    /// falls back to two-button mode when this is nil.
    private func fetchFeedSnapshotJSON(feedId: String) async -> String? {
        guard let feeds = try? await supabase.fetchFeeds() else { return nil }
        guard let feed = feeds.first(where: { $0.id == feedId }) else { return nil }
        let snap = FeedSettingsPayload(
            paused: feed.paused,
            maxArticlesPerDay: feed.maxArticlesPerDay,
            minScore: feed.minScore,
            ifMatch: nil
        )
        guard let data = try? JSONEncoder().encode(snap) else { return nil }
        return String(data: data, encoding: .utf8)
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

    /// Record reading position (0-100) for an article. Non-throwing — last
    /// writer wins and a dropped position update isn't user-visible. Coalesces
    /// through the queue on offline/failure like other mutations.
    func setReadingPosition(articleId: String, percent: Int) async {
        let clamped = max(0, min(100, percent))
        let payload = ReadingPositionPayload(percent: clamped)
        if isOffline {
            queueAction(type: "reading_position", articleId: articleId, payload: payload)
            return
        }
        do {
            try await supabase.updateReadingPosition(articleId: articleId, percent: clamped)
        } catch {
            queueAction(type: "reading_position", articleId: articleId, payload: payload)
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
    /// The action was parked in conflict state — caller should not delete it.
    case parkedAsConflict

    var errorDescription: String? {
        switch self {
        case .queuedOffline:
            return "Action queued — will sync when back online."
        case .parkedAsConflict:
            return "Action parked — waiting for conflict resolution."
        }
    }
}
