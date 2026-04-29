import Foundation
import os

// MARK: - Action-type mapping

/// Maps an action type string to its human-readable label and SF Symbol.
struct ActionTypeInfo {
    let label: String
    let icon: String

    static func for_(_ actionType: String, payload: String? = nil) -> ActionTypeInfo {
        switch actionType {
        case "read":
            return ActionTypeInfo(label: "Mark read", icon: "checkmark.circle")
        case "save":
            // Decode payload to distinguish save vs. unsave
            if let payload, let data = payload.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(SavePayloadPreview.self, from: data),
               !decoded.saved {
                return ActionTypeInfo(label: "Unsave article", icon: "bookmark")
            }
            return ActionTypeInfo(label: "Save article", icon: "bookmark")
        case "reaction":
            return ActionTypeInfo(label: "Set reaction", icon: "hand.thumbsup")
        case "tag_add":
            return ActionTypeInfo(label: "Add tag", icon: "tag")
        case "tag_remove":
            return ActionTypeInfo(label: "Remove tag", icon: "tag.slash")
        case "feed_settings":
            return ActionTypeInfo(label: "Update feed settings", icon: "slider.horizontal.3")
        case "subscribe_feed":
            return ActionTypeInfo(label: "Add feed", icon: "plus.rectangle.on.rectangle")
        case "unsubscribe_feed":
            return ActionTypeInfo(label: "Remove feed", icon: "minus.rectangle")
        case "reading_position":
            return ActionTypeInfo(label: "Save reading position", icon: "book")
        default:
            return ActionTypeInfo(label: actionType, icon: "questionmark.circle")
        }
    }
}

// Minimal decodable for save/unsave label disambiguation
private struct SavePayloadPreview: Decodable {
    let saved: Bool
}

// MARK: - SyncQueueRowDescriptor

/// A view-model value type derived from a `PendingAction`.
/// Pre-formats all display strings so row views are pure layout.
struct SyncQueueRowDescriptor: Identifiable, Hashable {
    let id: String
    let actionType: String
    let actionLabel: String
    let actionIcon: String
    let targetTitle: String
    let targetSubtitle: String?
    let enqueuedAge: String
    let retryCount: Int
    let nextAttemptCountdown: String?
    let lastErrorTail: String?
    let isConflict: Bool
    let rawPayloadJSON: String

    // MARK: - Factory

    /// Build a descriptor from a live `PendingAction` using the given caches.
    /// - Parameters:
    ///   - action: The queued action.
    ///   - cachedArticleTitle: Closure that looks up a CachedArticle title by id. May return nil.
    ///   - cachedFeedTitle: Closure that looks up a CachedFeed title by id. May return nil.
    ///   - isOffline: Whether the device currently lacks connectivity.
    static func from(
        _ action: PendingAction,
        cachedArticleTitle: (String) -> String?,
        cachedFeedTitle: (String) -> String?,
        isOffline: Bool,
        maxRetries: Int = 10
    ) -> SyncQueueRowDescriptor {
        let info = ActionTypeInfo.for_(action.actionType, payload: action.payload)

        let targetTitle = resolveTargetTitle(
            action: action,
            cachedArticleTitle: cachedArticleTitle,
            cachedFeedTitle: cachedFeedTitle
        )

        let targetSubtitle: String? = resolveSubtitle(action: action)

        let age = relativeAge(from: action.createdAt)

        let countdown: String?
        if action.retryCount >= maxRetries {
            // Dead-letter — no countdown
            countdown = nil
        } else {
            countdown = nextAttemptText(
                isOffline: isOffline,
                retryCount: action.retryCount,
                createdAt: action.createdAt
            )
        }

        let errorTail: String?
        if let err = action.lastError, !err.isEmpty {
            errorTail = String(err.suffix(80))
        } else {
            errorTail = nil
        }

        // Detect conflict via the `state` field added by the feed-settings-conflict-spec.
        // Falls back to lastError substring check for backward compatibility with rows
        // queued before the state field was added.
        let isConflict = action.state == "conflict"
            || action.lastError?.contains("412 Precondition Failed") == true

        return SyncQueueRowDescriptor(
            id: action.id,
            actionType: action.actionType,
            actionLabel: info.label,
            actionIcon: info.icon,
            targetTitle: targetTitle,
            targetSubtitle: targetSubtitle,
            enqueuedAge: age,
            retryCount: action.retryCount,
            nextAttemptCountdown: countdown,
            lastErrorTail: errorTail,
            isConflict: isConflict,
            rawPayloadJSON: action.payload
        )
    }

    // MARK: - Discard confirmation body

    /// Build the per-action-type body string for a discard confirmation alert.
    func discardConfirmationBody() -> String {
        switch actionType {
        case "read":
            return "The unread/read change for \(targetTitle) will be lost."
        case "save":
            return "The save/unsave change for \(targetTitle) will be lost."
        case "reaction":
            return "Your reaction on \(targetTitle) will be lost."
        case "tag_add":
            if let sub = targetSubtitle {
                return "The tag \(sub) will not be added to \(targetTitle)."
            }
            return "The tag will not be added to \(targetTitle)."
        case "tag_remove":
            return "The tag will not be removed from \(targetTitle)."
        case "feed_settings":
            if let sub = targetSubtitle {
                return "Your settings change for \(targetTitle) will be lost (\(sub))."
            }
            return "Your settings change for \(targetTitle) will be lost."
        case "subscribe_feed":
            return "\(targetTitle) will not be added to your feeds."
        case "unsubscribe_feed":
            return "\(targetTitle) will not be removed."
        case "reading_position":
            return "Your reading position for \(targetTitle) will be lost."
        default:
            return "This action for \(targetTitle) will be permanently discarded."
        }
    }
}

// MARK: - Private helpers

private func resolveTargetTitle(
    action: PendingAction,
    cachedArticleTitle: (String) -> String?,
    cachedFeedTitle: (String) -> String?
) -> String {
    switch action.actionType {
    case "read", "save", "reaction", "tag_add", "tag_remove", "reading_position":
        return cachedArticleTitle(action.articleId)
            ?? "Article \(String(action.articleId.prefix(8)))"
    case "feed_settings", "unsubscribe_feed":
        return cachedFeedTitle(action.articleId)
            ?? "Feed \(String(action.articleId.prefix(8)))"
    case "subscribe_feed":
        // articleId stores the URL directly for subscribe_feed
        return action.articleId
    default:
        return String(action.articleId.prefix(8))
    }
}

private func resolveSubtitle(action: PendingAction) -> String? {
    switch action.actionType {
    case "tag_add", "tag_remove":
        guard let data = action.payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TagPayloadPreview.self, from: data),
              let name = decoded.tagName else { return nil }
        return name
    case "feed_settings":
        // Build a brief diff summary from the payload
        guard let data = action.payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(FeedSettingsPayloadPreview.self, from: data) else {
            return nil
        }
        var parts: [String] = []
        if let paused = decoded.paused {
            parts.append(paused ? "paused" : "unpaused")
        }
        if let max = decoded.maxArticlesPerDay {
            parts.append("cap \(max)/day")
        }
        if let min = decoded.minScore {
            parts.append("min score \(min)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    default:
        return nil
    }
}

private struct TagPayloadPreview: Decodable {
    let tagName: String?
}

private struct FeedSettingsPayloadPreview: Decodable {
    let paused: Bool?
    let maxArticlesPerDay: Int?
    let minScore: Int?
}

private func relativeAge(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "just now"
    } else if interval < 3600 {
        let mins = Int(interval / 60)
        return "\(mins) min ago"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    } else {
        let days = Int(interval / 86400)
        return "\(days)d ago"
    }
}

private func nextAttemptText(isOffline: Bool, retryCount: Int, createdAt: Date) -> String {
    if isOffline {
        return "Waiting for network"
    }
    if retryCount == 0 {
        return "Sending\u{2026}"
    }
    // Approximate: SyncManager retries the whole queue on NWPath events, not per-row.
    let age = Date().timeIntervalSince(createdAt)
    if age < 60 {
        return "in <60s"
    }
    return "Pending next sync"
}
