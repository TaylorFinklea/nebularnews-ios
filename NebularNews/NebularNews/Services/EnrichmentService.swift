import Foundation
import NebularNewsKit

struct EnrichmentService: Sendable {
    private let api = APIClient.shared

    func fetchChat(articleId: String) async throws -> CompanionChatPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let payload: CompanionChatPayload = try await api.request(
            path: "api/chat/\(articleId)"
        )
        return payload
    }

    func sendChatMessage(articleId: String, content: String) async throws -> CompanionChatPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let message: String
        }

        let payload: CompanionChatPayload = try await api.request(
            method: "POST",
            path: "api/chat/\(articleId)",
            body: Body(message: content)
        )
        return payload
    }

    func fetchMultiChat() async throws -> CompanionChatPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let payload: CompanionChatPayload = try await api.request(path: "api/chat/multi")
        return payload
    }

    func sendMultiChatMessage(content: String) async throws -> CompanionChatPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let message: String
        }

        let payload: CompanionChatPayload = try await api.request(
            method: "POST",
            path: "api/chat/multi",
            body: Body(message: content)
        )
        return payload
    }

    func fetchSuggestedQuestions(articleId: String) async throws -> [String] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let questions: [String] = try await api.request(
            path: "api/enrich/\(articleId)/suggest-questions"
        )
        return questions
    }

    func requestSuggestedQuestions(articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(
            method: "POST",
            path: "api/enrich/\(articleId)/suggest-questions"
        )
    }

    func rerunSummarize(articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(
            method: "POST",
            path: "api/enrich/\(articleId)/summarize"
        )
    }

    func requestAIScore(articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(
            method: "POST",
            path: "api/enrich/\(articleId)/score"
        )
    }

    func generateKeyPoints(articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        try await api.requestVoid(
            method: "POST",
            path: "api/enrich/\(articleId)/key-points"
        )
    }

    func fetchFullContent(articleId: String) async throws -> FetchContentResult {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let result: FetchContentResult = try await api.request(
            method: "POST",
            path: "api/articles/\(articleId)/fetch-content"
        )
        return result
    }

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let brief: CompanionNewsBrief? = try await api.request(
            method: "POST",
            path: "api/brief/generate"
        )
        return brief
    }

    func fetchBriefHistory(before: Int? = nil, limit: Int = 20) async throws -> CompanionBriefHistoryPayload {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: String(before)))
        }

        let payload: CompanionBriefHistoryPayload = try await api.request(
            path: "api/brief/history",
            queryItems: query
        )
        return payload
    }

    func fetchBrief(id: String) async throws -> CompanionBriefDetail {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let detail: CompanionBriefDetail = try await api.request(
            path: "api/brief/\(id)"
        )
        return detail
    }
}
