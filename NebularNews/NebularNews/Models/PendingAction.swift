import Foundation
import SwiftData

@Model
final class PendingAction {
    @Attribute(.unique) var id: String = UUID().uuidString
    var actionType: String      // "read", "save", "reaction", "tag_add", "tag_remove"
    var articleId: String
    var payload: String          // JSON-encoded action data
    var createdAt: Date = Date()
    var retryCount: Int = 0
    var lastError: String?

    // MARK: - Conflict state fields (M12 If-Match / 412 conflict resolution)

    /// Lifecycle state: "pending" | "conflict" | "deadletter".
    /// `pending` covers both fresh and retrying-with-error rows.
    /// `conflict` parks the action for user resolution (no auto-retry).
    /// `deadletter` is what retryCount >= maxRetries means today — explicit
    /// field makes it queryable independently of the retry counter.
    var state: String = "pending"

    /// ETag captured at queue time. Sent as `If-Match` on retry to detect
    /// concurrent edits by another device.
    var ifMatchEtag: String?

    /// ETag returned by the server in the 412 response body. Stored so the
    /// conflict-resolution sheet can populate the "Server" column and so
    /// that the resolved payload can send the correct If-Match on re-submit.
    var conflictServerEtag: String?

    /// Best-effort JSON snapshot of the server's current row values at the
    /// time of the 412. Populated by re-fetching the feed list after a conflict.
    /// May be nil if the snapshot fetch failed — the conflict sheet falls back
    /// to a two-button (Keep server / Apply mine) mode in that case.
    var conflictServerSnapshotJSON: String?

    init(actionType: String, articleId: String, payload: String) {
        self.actionType = actionType
        self.articleId = articleId
        self.payload = payload
    }
}
