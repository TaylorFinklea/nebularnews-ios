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

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        let brief: CompanionNewsBrief? = try await api.request(
            method: "POST",
            path: "api/brief/generate"
        )
        return brief
    }
}
