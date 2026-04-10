import Foundation
import NebularNewsKit
import os

struct ArticleService: Sendable {
    private let api = APIClient.shared
    private let logger: Logger

    init(logger: Logger = Logger(subsystem: "com.nebularnews", category: "ArticleService")) {
        self.logger = logger
    }

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
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }

        if read != .all {
            queryItems.append(URLQueryItem(name: "read", value: read.rawValue))
        }

        if let minScore {
            queryItems.append(URLQueryItem(name: "minScore", value: String(minScore)))
        }

        if sort != .newest {
            queryItems.append(URLQueryItem(name: "sort", value: sort.rawValue))
        }

        if let tag {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }

        if saved {
            queryItems.append(URLQueryItem(name: "saved", value: "true"))
        }

        let payload: ArticlesPayload = try await api.request(
            path: "api/articles",
            queryItems: queryItems
        )
        return payload
    }

    func fetchArticle(id: String) async throws -> ArticleDetailPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let payload: ArticleDetailPayload = try await api.request(
            path: "api/articles/\(id)"
        )
        return payload
    }

    func setRead(articleId: String, isRead: Bool) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let isRead: Bool
        }
        try await api.requestVoid(
            method: "POST",
            path: "api/articles/\(articleId)/read",
            body: Body(isRead: isRead)
        )
    }

    func saveArticle(id: String, saved: Bool) async throws -> SaveResponse {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let saved: Bool
        }

        struct ServerSaveResponse: Decodable {
            let articleId: String
            let saved: Bool
            let savedAt: String?
        }

        let response: ServerSaveResponse = try await api.request(
            method: "POST",
            path: "api/articles/\(id)/save",
            body: Body(saved: saved)
        )

        return SaveResponse(articleId: response.articleId, saved: response.saved, savedAt: response.savedAt)
    }

    func dismissArticle(id: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(method: "POST", path: "api/articles/\(id)/dismiss")
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async throws -> ReactionResponse {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let value: Int
            let reasonCodes: [String]
        }

        struct ServerReactionResponse: Decodable {
            let articleId: String
            let value: Int
            let createdAt: String?
            let reasonCodes: [String]?
        }

        let response: ServerReactionResponse = try await api.request(
            method: "POST",
            path: "api/articles/\(articleId)/reaction",
            body: Body(value: value, reasonCodes: reasonCodes)
        )

        return ReactionResponse(
            articleId: response.articleId,
            value: response.value,
            createdAt: response.createdAt,
            reasonCodes: response.reasonCodes ?? reasonCodes
        )
    }

    // MARK: - Tags

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let name: String
        }

        let tags: [CompanionTag] = try await api.request(
            method: "POST",
            path: "api/articles/\(articleId)/tags",
            body: Body(name: name)
        )
        return tags
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let tags: [CompanionTag] = try await api.request(
            method: "DELETE",
            path: "api/articles/\(articleId)/tags/\(tagId)"
        )
        return tags
    }

    func fetchTags(query: String? = nil, limit: Int? = nil) async throws -> [CompanionTagWithCount] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        var queryItems: [URLQueryItem] = []
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        let tags: [CompanionTagWithCount] = try await api.request(
            path: "api/tags",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return tags
    }

    func createTag(name: String) async throws -> CompanionTagWithCount {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let name: String
        }

        let tag: CompanionTagWithCount = try await api.request(
            method: "POST",
            path: "api/tags",
            body: Body(name: name)
        )
        return tag
    }

    func deleteTag(id: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(method: "DELETE", path: "api/tags/\(id)")
    }

    // MARK: - Today

    func fetchToday() async throws -> CompanionTodayPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let payload: CompanionTodayPayload = try await api.request(path: "api/today")
        return payload
    }
}
