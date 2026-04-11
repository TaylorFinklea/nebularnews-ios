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

    func addFeed(url: String) async throws -> String {
        try await feedService.addFeed(url: url)
    }

    func deleteFeed(id: String) async throws {
        try await feedService.deleteFeed(id: id)
    }

    func updateFeedSettings(feedId: String, paused: Bool? = nil, maxArticlesPerDay: Int? = nil, minScore: Int? = nil) async throws {
        try await feedService.updateFeedSettings(feedId: feedId, paused: paused, maxArticlesPerDay: maxArticlesPerDay, minScore: minScore)
    }

    func updateFeedScrapeConfig(feedId: String, scrapeMode: String, scrapeProvider: String?, feedType: String) async throws {
        try await feedService.updateFeedScrapeConfig(feedId: feedId, scrapeMode: scrapeMode, scrapeProvider: scrapeProvider, feedType: feedType)
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

    // MARK: - News Brief

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        try await enrichmentService.generateNewsBrief()
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
}
