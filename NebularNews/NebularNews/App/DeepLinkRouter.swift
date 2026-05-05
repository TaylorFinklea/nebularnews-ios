import Foundation
import Observation

/// Routes deep link URLs (from widgets, notifications, etc.) to in-app destinations.
///
/// URL scheme:
/// - `nebularnews://today` — switch to the Today tab
/// - `nebularnews://article/{id}` — navigate to a specific article
/// - `nebularnews://brief/{id}` — open a specific news brief detail view
/// - `nebularnews://agent/{conversationId}` — switch to Agent tab + push that conversation
/// - `nebularnews://auth-callback` — handled by Supabase Auth (not routed here)
/// - `nebularnews://oauth/callback` — handled by legacy OAuth (not routed here)
@MainActor
@Observable
final class DeepLinkRouter {

    /// The article ID the user wants to open. Views observe this to push a detail view.
    var pendingArticleId: String?

    /// The brief ID the user wants to open. Today view observes this and pushes BriefDetailView.
    var pendingBriefId: String?

    /// The Agent conversation id the user wants to open. AgentConversationsView
    /// observes this and pushes the conversation. Cleared after read.
    var pendingAgentConversationId: String?

    /// Process an incoming deep link URL.
    /// Returns `true` if the URL was handled.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "nebularnews" else { return false }

        let host = url.host()

        switch host {
        case "today":
            // Clear any pending navigation — just switch to Today
            pendingArticleId = nil
            pendingBriefId = nil
            return true

        case "article":
            // URL: nebularnews://article/{articleId}
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let articleId = pathComponents.first, !articleId.isEmpty {
                pendingArticleId = articleId
                return true
            }
            return false

        case "brief":
            // URL: nebularnews://brief/{briefId}
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let briefId = pathComponents.first, !briefId.isEmpty {
                pendingBriefId = briefId
                return true
            }
            return false

        case "agent":
            // URL: nebularnews://agent/{conversationId}
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let conversationId = pathComponents.first, !conversationId.isEmpty {
                pendingAgentConversationId = conversationId
                return true
            }
            // Bare nebularnews://agent — just switch to the tab.
            return true

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

    func clearPendingBrief() {
        pendingBriefId = nil
    }

    func clearPendingAgentConversation() {
        pendingAgentConversationId = nil
    }
}
