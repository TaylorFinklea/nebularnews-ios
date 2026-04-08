import Foundation
import NebularNewsKit
import os
import Supabase

// MARK: - Supabase Manager

/// Central service that replaces MobileAPIClient with direct Supabase SDK calls.
///
/// Uses PostgREST for reads, direct table operations for writes, and
/// Supabase Edge Functions for AI-powered operations (enrichment, chat).
/// Auth is handled by the Supabase Auth module (Apple Sign In via ID token).
final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    private let logger = Logger(subsystem: "com.nebularnews", category: "SupabaseManager")
    private var authService: AuthService { AuthService(client: client) }
    private var articleService: ArticleService { ArticleService(client: client, logger: logger) }
    private var feedService: FeedService { FeedService(client: client) }
    private var enrichmentService: EnrichmentService { EnrichmentService(client: client) }

    private init() {
        guard let supabaseURL = URL(string: "https://vdjrclxeyjsqyqsjzjfj.supabase.co") else {
            preconditionFailure("Invalid Supabase URL")
        }
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkanJjbHhleWpzcXlxc2p6amZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NTk0OTIsImV4cCI6MjA5MDUzNTQ5Mn0.9j644tw6xud8GNW-J0X_sgtR_oyXGEoi59cN-O7wTHY",
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: "nebularnews://auth-callback"),
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    /// Current authenticated user ID, or nil if not signed in.
    var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
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
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let rows: [SupabaseUserSettingRow] = try await client.from("user_settings")
            .select("key, value")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        var settings = CompanionSettingsPayload(
            pollIntervalMinutes: 15,
            summaryStyle: "concise",
            scoringMethod: "ai",
            newsBriefConfig: CompanionNewsBriefConfig(
                enabled: true,
                timezone: TimeZone.current.identifier,
                morningTime: "08:00",
                eveningTime: "17:00",
                lookbackHours: 12,
                scoreCutoff: 3
            ),
            upNextLimit: 6,
            retentionArchiveDays: 30,
            retentionDeleteDays: 90
        )

        for row in rows {
            switch row.key {
            case "pollIntervalMinutes":
                settings.pollIntervalMinutes = Int(row.value) ?? settings.pollIntervalMinutes
            case "summaryStyle":
                settings.summaryStyle = row.value
            case "scoringMethod":
                settings.scoringMethod = row.value
            case "upNextLimit":
                settings.upNextLimit = Int(row.value) ?? settings.upNextLimit
            case "retentionArchiveDays":
                settings.retentionArchiveDays = Int(row.value)
            case "retentionDeleteDays":
                settings.retentionDeleteDays = Int(row.value)
            case "newsBriefEnabled":
                settings.newsBriefConfig.enabled = row.value == "true"
            case "newsBriefTimezone":
                settings.newsBriefConfig.timezone = row.value
            case "newsBriefMorningTime":
                settings.newsBriefConfig.morningTime = row.value
            case "newsBriefEveningTime":
                settings.newsBriefConfig.eveningTime = row.value
            case "newsBriefLookbackHours":
                settings.newsBriefConfig.lookbackHours = Int(row.value) ?? settings.newsBriefConfig.lookbackHours
            case "newsBriefScoreCutoff":
                settings.newsBriefConfig.scoreCutoff = Int(row.value) ?? settings.newsBriefConfig.scoreCutoff
            default:
                break
            }
        }

        return settings
    }

    func updateSettings(_ settings: CompanionSettingsPayload) async throws -> CompanionSettingsPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let pairs: [(String, String)] = [
            ("pollIntervalMinutes", String(settings.pollIntervalMinutes)),
            ("summaryStyle", settings.summaryStyle),
            ("scoringMethod", settings.scoringMethod),
            ("upNextLimit", String(settings.upNextLimit)),
            ("retentionArchiveDays", String(settings.retentionArchiveDays ?? 30)),
            ("retentionDeleteDays", String(settings.retentionDeleteDays ?? 90)),
            ("newsBriefEnabled", settings.newsBriefConfig.enabled ? "true" : "false"),
            ("newsBriefTimezone", settings.newsBriefConfig.timezone),
            ("newsBriefMorningTime", settings.newsBriefConfig.morningTime),
            ("newsBriefEveningTime", settings.newsBriefConfig.eveningTime),
            ("newsBriefLookbackHours", String(settings.newsBriefConfig.lookbackHours)),
            ("newsBriefScoreCutoff", String(settings.newsBriefConfig.scoreCutoff))
        ]

        let upserts = pairs.map { (key, value) in
            UserSettingUpsert(userId: userId.uuidString, key: key, value: value)
        }

        try await client.from("user_settings")
            .upsert(upserts, onConflict: "user_id,key")
            .execute()

        return settings
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
