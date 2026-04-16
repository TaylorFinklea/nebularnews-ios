import Foundation

struct HighlightService: Sendable {
    private let api = APIClient.shared

    func fetchHighlights(articleId: String) async throws -> [CompanionHighlight] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/articles/\(articleId)/highlights")
    }

    func createHighlight(
        articleId: String,
        selectedText: String,
        blockIndex: Int? = nil,
        textOffset: Int? = nil,
        textLength: Int? = nil,
        note: String? = nil,
        color: String? = nil
    ) async throws -> CompanionHighlight {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let selectedText: String
            let blockIndex: Int?
            let textOffset: Int?
            let textLength: Int?
            let note: String?
            let color: String?
        }

        return try await api.request(
            method: "POST",
            path: "api/articles/\(articleId)/highlights",
            body: Body(selectedText: selectedText, blockIndex: blockIndex, textOffset: textOffset, textLength: textLength, note: note, color: color)
        )
    }

    func updateHighlight(articleId: String, highlightId: String, note: String?, color: String? = nil) async throws -> CompanionHighlight {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let note: String?
            let color: String?
        }

        return try await api.request(
            method: "PATCH",
            path: "api/articles/\(articleId)/highlights/\(highlightId)",
            body: Body(note: note, color: color)
        )
    }

    func deleteHighlight(articleId: String, highlightId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        try await api.requestVoid(method: "DELETE", path: "api/articles/\(articleId)/highlights/\(highlightId)")
    }
}
