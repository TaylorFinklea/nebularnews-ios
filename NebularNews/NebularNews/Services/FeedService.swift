import Foundation
import NebularNewsKit

struct FeedService: Sendable {
    private let api = APIClient.shared

    func fetchFeeds() async throws -> [CompanionFeed] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let feeds: [CompanionFeed] = try await api.request(path: "api/feeds")
        return feeds
    }

    func addFeed(url: String, scrapeMode: String? = nil) async throws -> String {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let url: String
            let scrapeMode: String?
        }

        struct AddFeedResponse: Decodable {
            let id: String
        }

        let response: AddFeedResponse = try await api.request(
            method: "POST",
            path: "api/feeds",
            body: Body(url: url, scrapeMode: scrapeMode)
        )
        return response.id
    }

    func deleteFeed(id: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(method: "DELETE", path: "api/feeds/\(id)")
    }

    func updateFeedSettings(feedId: String, paused: Bool? = nil, maxArticlesPerDay: Int? = nil, minScore: Int? = nil) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let paused: Bool?
            let maxArticlesPerDay: Int?
            let minScore: Int?
        }

        try await api.requestVoid(
            method: "PATCH",
            path: "api/feeds/\(feedId)/settings",
            body: Body(paused: paused, maxArticlesPerDay: maxArticlesPerDay, minScore: minScore)
        )
    }

    func updateScrapeMode(feedId: String, scrapeMode: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let scrapeMode: String
        }

        try await api.requestVoid(
            method: "PATCH",
            path: "api/feeds/\(feedId)",
            body: Body(scrapeMode: scrapeMode)
        )
    }

    func importOPML(xml: String) async throws -> Int {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let xml: String
        }

        struct ImportResponse: Decodable {
            let added: Int
        }

        let response: ImportResponse = try await api.request(
            method: "POST",
            path: "api/feeds/import-opml",
            body: Body(xml: xml)
        )
        return response.added
    }

    func exportOPML() async throws -> String {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct ExportResponse: Decodable {
            let opml: String
        }

        let response: ExportResponse = try await api.request(path: "api/feeds/export-opml")
        return response.opml
    }

    @discardableResult
    func triggerPull(cycles: Int = 1) async throws -> Void {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(method: "POST", path: "api/feeds/trigger-pull")
    }

    func fetchOnboardingSuggestions() async throws -> OnboardingCatalog {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let catalog: OnboardingCatalog = try await api.request(path: "api/onboarding/suggestions")
        return catalog
    }

    func bulkSubscribe(feedUrls: [String]) async throws -> Int {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let feedUrls: [String]
        }

        struct BulkResponse: Decodable {
            let subscribed: Int
        }

        let response: BulkResponse = try await api.request(
            method: "POST",
            path: "api/onboarding/bulk-subscribe",
            body: Body(feedUrls: feedUrls)
        )
        return response.subscribed
    }
}
