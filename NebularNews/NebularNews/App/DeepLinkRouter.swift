import Foundation
import Observation

/// Routes deep link URLs (from widgets, notifications, etc.) to in-app destinations.
///
/// URL scheme:
/// - `nebularnews://today` — switch to the Today tab
/// - `nebularnews://article/{id}` — navigate to a specific article
/// - `nebularnews://auth-callback` — handled by Supabase Auth (not routed here)
/// - `nebularnews://oauth/callback` — handled by legacy OAuth (not routed here)
@MainActor
@Observable
final class DeepLinkRouter {

    /// The article ID the user wants to open. Views observe this to push a detail view.
    var pendingArticleId: String?

    /// Process an incoming deep link URL.
    /// Returns `true` if the URL was handled.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "nebularnews" else { return false }

        let host = url.host()

        switch host {
        case "today":
            // Clear any pending article — just switch to Today
            pendingArticleId = nil
            return true

        case "article":
            // URL: nebularnews://article/{articleId}
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let articleId = pathComponents.first, !articleId.isEmpty {
                pendingArticleId = articleId
                return true
            }
            return false

        case "auth-callback", "oauth":
            // Handled by Supabase Auth / legacy OAuth — not our concern
            return false

        default:
            return false
        }
    }

    /// Clear the pending navigation after the destination view has appeared.
    func clearPendingArticle() {
        pendingArticleId = nil
    }
}
