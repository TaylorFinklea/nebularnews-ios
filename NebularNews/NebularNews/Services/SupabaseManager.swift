import Foundation
import NebularNewsKit
import os

// MARK: - Supabase Manager

/// Central service facade that delegates to domain-specific service structs.
///
/// Previously used the Supabase SDK directly; now delegates to APIClient
/// which calls the Cloudflare Workers REST API. The class name is preserved
/// to avoid cascading renames across all SwiftUI views.
final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    private let logger = Logger(subsystem: "com.nebularnews", category: "SupabaseManager")
    private let api = APIClient.shared
    private var authService: AuthService { AuthService() }
    private var articleService: ArticleService { ArticleService(logger: logger) }
    private var feedService: FeedService { FeedService() }
    private var enrichmentService: EnrichmentService { EnrichmentService() }
    private var collectionService: CollectionService { CollectionService() }
    private var highlightService: HighlightService { HighlightService() }
    private var annotationService: AnnotationService { AnnotationService() }

    private init() {}

    /// Current authenticated user ID, or nil if not signed in.
    var currentUserId: String? {
        get async {
            guard let session = try? await authService.session() else { return nil }
            return session.user.id
        }
    }

    // MARK: - Auth

    /// Sign in with an Apple ID token from AuthenticationServices.
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await authService.signInWithApple(idToken: idToken, nonce: nonce)
    }

    func signOut() async throws {
        try await authService.signOut()
    }

    func session() async throws -> Session {
        try await authService.session()
    }

    // MARK: - Articles

    func fetchArticles(
        query: String = "",
        offset: Int = 0,
        limit: Int = 20,
        read: ReadFilter = .all,
        minScore: Int? = nil,
        sort: SortOrder = .newest,
        sinceDays: Int? = nil,
        tag: String? = nil,
        saved: Bool = false
    ) async throws -> ArticlesPayload {
        try await articleService.fetchArticles(
            query: query,
            offset: offset,
            limit: limit,
            read: read,
            minScore: minScore,
            sort: sort,
            sinceDays: sinceDays,
            tag: tag,
            saved: saved
        )
    }

    func fetchArticle(id: String) async throws -> ArticleDetailPayload {
        try await articleService.fetchArticle(id: id)
    }

    func setRead(articleId: String, isRead: Bool) async throws {
        try await articleService.setRead(articleId: articleId, isRead: isRead)
    }

    func saveArticle(id: String, saved: Bool) async throws -> SaveResponse {
        try await articleService.saveArticle(id: id, saved: saved)
    }

    func dismissArticle(id: String) async throws {
        try await articleService.dismissArticle(id: id)
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async throws -> ReactionResponse {
        try await articleService.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes)
    }

    // MARK: - Tags

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        try await articleService.addTag(articleId: articleId, name: name)
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        try await articleService.removeTag(articleId: articleId, tagId: tagId)
    }

    func fetchTags(query: String? = nil, limit: Int? = nil) async throws -> [CompanionTagWithCount] {
        try await articleService.fetchTags(query: query, limit: limit)
    }

    func createTag(name: String) async throws -> CompanionTagWithCount {
        try await articleService.createTag(name: name)
    }

    func deleteTag(id: String) async throws {
        try await articleService.deleteTag(id: id)
    }

    // MARK: - Feeds

    func fetchFeeds() async throws -> [CompanionFeed] {
        try await feedService.fetchFeeds()
    }

    func addFeed(url: String, scrapeMode: String? = nil) async throws -> String {
        try await feedService.addFeed(url: url, scrapeMode: scrapeMode)
    }

    func deleteFeed(id: String) async throws {
        try await feedService.deleteFeed(id: id)
    }

    @discardableResult
    func updateFeedSettings(
        feedId: String,
        paused: Bool? = nil,
        maxArticlesPerDay: Int? = nil,
        minScore: Int? = nil,
        ifMatch: String? = nil
    ) async throws -> String? {
        try await feedService.updateFeedSettings(
            feedId: feedId,
            paused: paused,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore,
            ifMatch: ifMatch
        )
    }

    func updateScrapeMode(feedId: String, scrapeMode: String) async throws {
        try await feedService.updateScrapeMode(feedId: feedId, scrapeMode: scrapeMode)
    }

    func importOPML(xml: String) async throws -> Int {
        try await feedService.importOPML(xml: xml)
    }

    func exportOPML() async throws -> String {
        try await feedService.exportOPML()
    }

    @discardableResult
    func triggerPull(cycles: Int = 1) async throws -> Void {
        try await feedService.triggerPull(cycles: cycles)
    }

    // MARK: - Today

    func fetchToday() async throws -> CompanionTodayPayload {
        try await articleService.fetchToday()
    }

    // MARK: - Settings

    func fetchSettings() async throws -> CompanionSettingsPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let settings: CompanionSettingsPayload = try await api.request(path: "api/settings")
        return settings
    }

    func updateSettings(_ settings: CompanionSettingsPayload) async throws -> CompanionSettingsPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let updated: CompanionSettingsPayload = try await api.request(
            method: "PUT",
            path: "api/settings",
            body: settings
        )
        return updated
    }

    // MARK: - Chat

    func fetchChat(articleId: String) async throws -> CompanionChatPayload {
        try await enrichmentService.fetchChat(articleId: articleId)
    }

    func sendChatMessage(articleId: String, content: String) async throws -> CompanionChatPayload {
        try await enrichmentService.sendChatMessage(articleId: articleId, content: content)
    }

    func fetchMultiChat() async throws -> CompanionChatPayload {
        try await enrichmentService.fetchMultiChat()
    }

    func sendMultiChatMessage(content: String) async throws -> CompanionChatPayload {
        try await enrichmentService.sendMultiChatMessage(content: content)
    }

    func fetchSuggestedQuestions(articleId: String) async throws -> [String] {
        try await enrichmentService.fetchSuggestedQuestions(articleId: articleId)
    }

    func requestSuggestedQuestions(articleId: String) async throws {
        try await enrichmentService.requestSuggestedQuestions(articleId: articleId)
    }

    // MARK: - AI Operations

    func rerunSummarize(articleId: String) async throws {
        try await enrichmentService.rerunSummarize(articleId: articleId)
    }

    func requestAIScore(articleId: String) async throws {
        try await enrichmentService.requestAIScore(articleId: articleId)
    }

    func generateKeyPoints(articleId: String) async throws {
        try await enrichmentService.generateKeyPoints(articleId: articleId)
    }

    func fetchFullContent(articleId: String) async throws -> FetchContentResult {
        try await enrichmentService.fetchFullContent(articleId: articleId)
    }

    // MARK: - News Brief

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        try await enrichmentService.generateNewsBrief()
    }

    func updateReadingPosition(articleId: String, percent: Int, timeSpentMs: Int? = nil) async throws {
        try await articleService.updateReadingPosition(articleId: articleId, percent: percent, timeSpentMs: timeSpentMs)
    }

    func fetchBriefHistory(before: Int? = nil, limit: Int = 20) async throws -> CompanionBriefHistoryPayload {
        try await enrichmentService.fetchBriefHistory(before: before, limit: limit)
    }

    func fetchBrief(id: String) async throws -> CompanionBriefDetail {
        try await enrichmentService.fetchBrief(id: id)
    }

    /// Daily conversation history — list every day with at least one
    /// message in the assistant thread. Server groups by user-local day.
    func fetchConversationDays() async throws -> [CompanionConversationDay] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        let payload: CompanionConversationDaysPayload = try await api.request(
            path: "api/chat/assistant/days"
        )
        return payload.days
    }

    /// Read-only message list for one historical day (`YYYY-MM-DD`).
    func fetchConversationDay(date: String) async throws -> CompanionConversationDayDetail {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/chat/assistant/day/\(date)")
    }

    // MARK: - Agent conversations (Build 37)

    /// List the user's Agent conversations, newest first. Server-side
    /// filter excludes the legacy multi-chat sentinel and any thread
    /// that's brief_seed-only (those live on Today's brief history).
    func fetchAgentConversations() async throws -> [AgentConversationSummary] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        do {
            return try await api.request(path: "api/chat/agent/conversations")
        } catch let error as DecodingError {
            // Surface the failing key path / type info so we don't get
            // the generic "data couldn't be read" string when something
            // server-side returns an unexpected shape.
            throw SupabaseManagerError.decodingFailed(detail: prettyDecodingError(error))
        }
    }

    private func prettyDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let ctx):
            return "type mismatch on \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
        case .valueNotFound(let type, let ctx):
            return "missing value at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): expected \(type)"
        case .keyNotFound(let key, let ctx):
            return "missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx):
            return "data corrupted at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    /// Create a new Agent conversation. Optional pinned article id
    /// (used when "Tell me more" or "Open in Agent" originated the
    /// conversation). Title is left null until the first user message
    /// commits — server auto-titles via heuristic.
    func createAgentConversation(articleId: String? = nil, title: String? = nil) async throws -> AgentConversationSummary {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        struct Body: Encodable { let articleId: String?; let title: String? }
        return try await api.request(
            method: "POST",
            path: "api/chat/agent/conversations",
            body: Body(articleId: articleId, title: title)
        )
    }

    /// Load full message list for one conversation. Server filters out
    /// system markers + brief_seed rows so the Agent surface renders
    /// directly without per-row guards.
    func fetchAgentConversation(id: String) async throws -> AgentConversationDetail {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/chat/agent/conversations/\(id)")
    }

    /// Rename a conversation. Length is server-capped at 120 chars.
    func renameAgentConversation(id: String, title: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        struct Body: Encodable { let title: String }
        try await api.requestVoid(
            method: "PATCH",
            path: "api/chat/agent/conversations/\(id)",
            body: Body(title: title)
        )
    }

    /// Soft-delete a conversation. Messages stay in the DB; the row
    /// vanishes from the list and from the chat thread fetch.
    func deleteAgentConversation(id: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        try await api.requestVoid(
            method: "DELETE",
            path: "api/chat/agent/conversations/\(id)"
        )
    }

    /// Persist a {user, assistant} turn the iOS client generated locally
    /// (free-tier on-device AI). The server only stores the rows; no LLM
    /// is invoked. Used by `OnDeviceAssistantStream` to keep the Agent
    /// conversation list in sync with what the user sees on-device.
    @discardableResult
    func persistAssistantMessages(
        userMessage: String,
        assistantMessage: String
    ) async throws -> CompanionAssistantPersistResult {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        struct Body: Encodable {
            let user_message: String
            let assistant_message: String
        }
        return try await api.request(
            method: "POST",
            path: "api/chat/assistant/persist",
            body: Body(user_message: userMessage, assistant_message: assistantMessage)
        )
    }

    /// Weekly reading insight (cached server-side per user, regenerates
    /// once a week). Surfaces on Today as a dismissable card.
    func fetchWeeklyInsight() async throws -> CompanionWeeklyInsight {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/insights/weekly")
    }

    // MARK: - Device Token

    func registerDeviceToken(token: String) async throws {
        try await authService.registerDeviceToken(token: token)
    }

    func removeDeviceToken(token: String) async throws {
        try await authService.removeDeviceToken(token: token)
    }

    // MARK: - Onboarding

    func fetchOnboardingSuggestions() async throws -> OnboardingCatalog {
        try await feedService.fetchOnboardingSuggestions()
    }

    func bulkSubscribe(feedUrls: [String]) async throws -> Int {
        try await feedService.bulkSubscribe(feedUrls: feedUrls)
    }

    // MARK: - Collections

    func fetchCollections() async throws -> [CompanionCollection] {
        try await collectionService.fetchCollections()
    }

    func createCollection(name: String, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> CompanionCollection {
        try await collectionService.createCollection(name: name, description: description, color: color, icon: icon)
    }

    func fetchCollection(id: String) async throws -> CompanionCollectionDetail {
        try await collectionService.fetchCollection(id: id)
    }

    func updateCollection(id: String, name: String? = nil, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> CompanionCollection {
        try await collectionService.updateCollection(id: id, name: name, description: description, color: color, icon: icon)
    }

    func deleteCollection(id: String) async throws {
        try await collectionService.deleteCollection(id: id)
    }

    func addArticleToCollection(collectionId: String, articleId: String) async throws -> CompanionCollectionArticleResponse {
        try await collectionService.addArticle(collectionId: collectionId, articleId: articleId)
    }

    func removeArticleFromCollection(collectionId: String, articleId: String) async throws {
        try await collectionService.removeArticle(collectionId: collectionId, articleId: articleId)
    }

    func fetchArticleCollections(articleId: String) async throws -> [CompanionCollection] {
        try await collectionService.fetchArticleCollections(articleId: articleId)
    }

    // MARK: - Highlights

    func fetchHighlights(articleId: String) async throws -> [CompanionHighlight] {
        try await highlightService.fetchHighlights(articleId: articleId)
    }

    func createHighlight(articleId: String, selectedText: String, blockIndex: Int? = nil, textOffset: Int? = nil, textLength: Int? = nil, note: String? = nil, color: String? = nil) async throws -> CompanionHighlight {
        try await highlightService.createHighlight(articleId: articleId, selectedText: selectedText, blockIndex: blockIndex, textOffset: textOffset, textLength: textLength, note: note, color: color)
    }

    func updateHighlight(articleId: String, highlightId: String, note: String?, color: String? = nil) async throws -> CompanionHighlight {
        try await highlightService.updateHighlight(articleId: articleId, highlightId: highlightId, note: note, color: color)
    }

    func deleteHighlight(articleId: String, highlightId: String) async throws {
        try await highlightService.deleteHighlight(articleId: articleId, highlightId: highlightId)
    }

    // MARK: - Annotations

    func fetchAnnotation(articleId: String) async throws -> CompanionAnnotation? {
        try await annotationService.fetchAnnotation(articleId: articleId)
    }

    func upsertAnnotation(articleId: String, content: String) async throws -> CompanionAnnotation {
        try await annotationService.upsertAnnotation(articleId: articleId, content: content)
    }

    func deleteAnnotation(articleId: String) async throws {
        try await annotationService.deleteAnnotation(articleId: articleId)
    }
}
