import Foundation

struct CollectionService: Sendable {
    private let api = APIClient.shared

    func fetchCollections() async throws -> [CompanionCollection] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/collections")
    }

    func createCollection(name: String, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> CompanionCollection {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let name: String
            let description: String?
            let color: String?
            let icon: String?
        }

        return try await api.request(
            method: "POST",
            path: "api/collections",
            body: Body(name: name, description: description, color: color, icon: icon)
        )
    }

    func fetchCollection(id: String) async throws -> CompanionCollectionDetail {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/collections/\(id)")
    }

    func updateCollection(id: String, name: String? = nil, description: String? = nil, color: String? = nil, icon: String? = nil) async throws -> CompanionCollection {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let name: String?
            let description: String?
            let color: String?
            let icon: String?
        }

        return try await api.request(
            method: "PATCH",
            path: "api/collections/\(id)",
            body: Body(name: name, description: description, color: color, icon: icon)
        )
    }

    func deleteCollection(id: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        try await api.requestVoid(method: "DELETE", path: "api/collections/\(id)")
    }

    func addArticle(collectionId: String, articleId: String) async throws -> CompanionCollectionArticleResponse {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        struct Body: Encodable {
            let articleId: String
        }

        return try await api.request(
            method: "POST",
            path: "api/collections/\(collectionId)/articles",
            body: Body(articleId: articleId)
        )
    }

    func removeArticle(collectionId: String, articleId: String) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        try await api.requestVoid(method: "DELETE", path: "api/collections/\(collectionId)/articles/\(articleId)")
    }

    func fetchArticleCollections(articleId: String) async throws -> [CompanionCollection] {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }
        return try await api.request(path: "api/articles/\(articleId)/collections")
    }
}
