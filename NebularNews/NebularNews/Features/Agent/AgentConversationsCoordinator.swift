import Foundation
import SwiftUI
import os

/// Owns the Agent tab's conversation list and coordinates loading the
/// active conversation through `AIAssistantCoordinator` (which still
/// handles streaming + tool dispatch + state for one thread at a time).
///
/// Switching conversations resets the inner coordinator's state and
/// reloads the new thread — equivalent to ChatGPT's "open conversation"
/// behavior where in-flight state of the previous chat is dropped on
/// switch and reloaded from the server when revisited.
@MainActor
@Observable
final class AgentConversationsCoordinator {
    private let logger = Logger(subsystem: "com.nebularnews", category: "AgentCoordinator")

    /// Newest-first list of the user's conversations. Empty until
    /// `refresh()` runs.
    private(set) var conversations: [AgentConversationSummary] = []

    /// True while the list is loading (initial load or refresh).
    private(set) var isLoadingList = false

    /// The conversation the user has currently pushed into. Cleared
    /// when they pop back to the list.
    private(set) var activeConversationId: String?

    /// Surfaced to the list UI when the load fails. nil otherwise.
    private(set) var errorMessage: String?

    func refresh() async {
        isLoadingList = true
        defer { isLoadingList = false }
        do {
            conversations = try await SupabaseManager.shared.fetchAgentConversations()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Conversation list fetch failed: \(error.localizedDescription)")
        }
    }

    /// Insert a new conversation row at the top after creation. Used
    /// when "+" toolbar button or pending pendingAgentConversation flow
    /// creates a fresh conversation server-side.
    func insertNew(_ summary: AgentConversationSummary) {
        conversations.removeAll { $0.id == summary.id }
        conversations.insert(summary, at: 0)
    }

    /// Apply a rename to the local list without re-fetching.
    func updateTitle(id: String, title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        let old = conversations[idx]
        conversations[idx] = AgentConversationSummary(
            id: old.id,
            articleId: old.articleId,
            title: title,
            lastMessagePreview: old.lastMessagePreview,
            messageCount: old.messageCount,
            updatedAt: Int(Date().timeIntervalSince1970 * 1000),
            createdAt: old.createdAt,
            hasPinnedArticle: old.hasPinnedArticle
        )
    }

    /// Drop a soft-deleted conversation from the local list.
    func remove(id: String) {
        conversations.removeAll { $0.id == id }
    }

    /// Mark the active conversation. Called by `AgentConversationView`
    /// on appear so the coordinator knows which one's open.
    func setActive(_ id: String?) {
        activeConversationId = id
    }
}
