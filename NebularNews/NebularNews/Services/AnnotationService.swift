import Foundation

struct AnnotationService: Sendable {
    private let api = APIClient.shared

    func fetchAnnotation(articleId: String) async throws -> CompanionAnnotation? {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/articles/\(articleId)/annotation")
    }

    func upsertAnnotation(articleId: String, content: String) async throws -> CompanionAnnotation {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let content: String
        }

        return try await api.request(
            method: "PUT",
            path: "api/articles/\(articleId)/annotation",
            body: Body(content: content)
        )
    }

    func deleteAnnotation(articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        try await api.requestVoid(method: "DELETE", path: "api/articles/\(articleId)/annotation")
    }
}
