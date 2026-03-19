import Foundation
import NebularNewsKit

enum MobileAPIError: LocalizedError {
    case missingServerURL
    case missingRefreshToken
    case invalidResponse
    case unexpectedEmptyResponse
    case server(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            return "Connect the app to a Nebular News server first."
        case .missingRefreshToken:
            return "Your sign-in session expired. Sign in again."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .unexpectedEmptyResponse:
            return "Expected a response body but received none."
        case .server(let message):
            return message
        case .unauthorized:
            return "Your sign-in session is no longer valid."
        }
    }
}

final class MobileAPIClient {
    private let configuration: AppConfiguration
    private let keychain: KeychainManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: AppConfiguration, keychain: KeychainManager) {
        self.configuration = configuration
        self.keychain = keychain
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func fetchSession() async throws -> CompanionSessionPayload {
        try await get("/api/mobile/session")
    }

    func fetchDashboard() async throws -> CompanionDashboardPayload {
        try await get("/api/mobile/dashboard")
    }

    func fetchFeeds() async throws -> [CompanionFeed] {
        let payload: CompanionFeedListPayload = try await get("/api/mobile/feeds")
        return payload.feeds
    }

    func fetchArticles(
        query: String = "",
        offset: Int = 0,
        limit: Int = 20,
        read: CompanionReadFilter = .all,
        minScore: Int? = nil,
        sort: CompanionSortOrder = .newest,
        sinceDays: Int? = nil,
        tag: String? = nil
    ) async throws -> CompanionArticlesPayload {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }
        if read != .all {
            components.queryItems?.append(URLQueryItem(name: "read", value: read.rawValue))
        }
        if let minScore {
            components.queryItems?.append(URLQueryItem(name: "score", value: String(minScore)))
        }
        if sort != .newest {
            components.queryItems?.append(URLQueryItem(name: "sort", value: sort.rawValue))
        }
        if let sinceDays {
            components.queryItems?.append(URLQueryItem(name: "sinceDays", value: String(sinceDays)))
        }
        if let tag {
            components.queryItems?.append(URLQueryItem(name: "tag", value: tag))
        }
        let queryString = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await get("/api/mobile/articles\(queryString)")
    }

    func fetchArticle(id: String) async throws -> CompanionArticleDetailPayload {
        try await get("/api/mobile/articles/\(id)")
    }

    func setRead(articleId: String, isRead: Bool) async throws {
        struct Body: Encodable { let isRead: Bool }
        let _: EmptyPayload = try await post("/api/mobile/articles/\(articleId)/read", body: Body(isRead: isRead))
    }

    func setReaction(articleId: String, value: Int, reasonCodes: [String]) async throws -> CompanionReaction {
        struct Body: Encodable {
            let value: Int
            let reasonCodes: [String]
        }
        let response: CompanionReactionResponse = try await post(
            "/api/mobile/articles/\(articleId)/reaction",
            body: Body(value: value, reasonCodes: reasonCodes)
        )
        return response.reaction
    }

    func addTag(articleId: String, name: String) async throws -> [CompanionTag] {
        struct Body: Encodable {
            let source = "manual"
            let addTagNames: [String]
        }
        let response: CompanionTagMutationResponse = try await post(
            "/api/mobile/articles/\(articleId)/tags",
            body: Body(addTagNames: [name])
        )
        return response.tags
    }

    func removeTag(articleId: String, tagId: String) async throws -> [CompanionTag] {
        struct Body: Encodable {
            let removeTagIds: [String]
        }
        let response: CompanionTagMutationResponse = try await post(
            "/api/mobile/articles/\(articleId)/tags",
            body: Body(removeTagIds: [tagId])
        )
        return response.tags
    }

    // MARK: - Feed management

    func addFeed(url: String) async throws -> CompanionAddFeedResponse {
        struct Body: Encodable { let url: String }
        return try await post("/api/mobile/feeds", body: Body(url: url))
    }

    func deleteFeed(id: String) async throws -> CompanionDeleteFeedResponse {
        try await delete("/api/mobile/feeds/\(id)")
    }

    func importOPML(xml: String) async throws -> CompanionImportOPMLResponse {
        struct Body: Encodable { let opml: String }
        return try await post("/api/mobile/feeds/import", body: Body(opml: xml))
    }

    func exportOPML() async throws -> String {
        try await getRawString("/api/mobile/feeds/export")
    }

    func triggerPull(cycles: Int = 1) async throws -> CompanionTriggerPullResponse {
        struct Body: Encodable { let cycles: Int }
        return try await post("/api/mobile/pull", body: Body(cycles: cycles))
    }

    func clearSession() {
        keychain.delete(forKey: KeychainManager.Key.syncAccessToken)
        keychain.delete(forKey: KeychainManager.Key.syncRefreshToken)
        keychain.delete(forKey: KeychainManager.Key.syncServerUrl)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await authorizedRequest(path: path, method: "GET", bodyData: nil, decode: T.self)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await authorizedRequest(path: path, method: "POST", bodyData: try encoder.encode(body), decode: T.self)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await authorizedRequest(path: path, method: "DELETE", bodyData: nil, decode: T.self)
    }

    private func getRawString(_ path: String) async throws -> String {
        let serverURL = try serverURL()
        let accessToken = try await accessToken()
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobileAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw try decodeServerError(from: data, statusCode: httpResponse.statusCode)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw MobileAPIError.invalidResponse
        }
        return string
    }

    private func authorizedRequest<T: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        decode: T.Type,
        retryingAfterRefresh: Bool = false
    ) async throws -> T {
        let serverURL = try serverURL()
        let accessToken = try await accessToken()
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobileAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            guard !retryingAfterRefresh else {
                throw MobileAPIError.unauthorized
            }
            _ = try await refreshAccessToken()
            return try await authorizedRequest(
                path: path,
                method: method,
                bodyData: bodyData,
                decode: decode,
                retryingAfterRefresh: true
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw try decodeServerError(from: data, statusCode: httpResponse.statusCode)
        }
        if decode == EmptyPayload.self {
            guard let empty = EmptyPayload() as? T else {
                throw MobileAPIError.unexpectedEmptyResponse
            }
            return empty
        }
        return try decoder.decode(decode, from: data)
    }

    private func accessToken() async throws -> String {
        if let token = keychain.get(forKey: KeychainManager.Key.syncAccessToken), !token.isEmpty {
            return token
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        let serverURL = try serverURL()
        guard let refreshToken = keychain.get(forKey: KeychainManager.Key.syncRefreshToken), !refreshToken.isEmpty else {
            throw MobileAPIError.missingRefreshToken
        }

        var request = URLRequest(url: serverURL.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLComponents.formEncodedData([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: configuration.mobileOAuthClientId),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "resource", value: serverURL.appending(path: "api/mobile").absoluteString)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobileAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            clearSession()
            throw try decodeServerError(from: data, statusCode: httpResponse.statusCode)
        }

        let tokenResponse = try decoder.decode(MobileTokenResponse.self, from: data)
        try keychain.set(tokenResponse.accessToken, forKey: KeychainManager.Key.syncAccessToken)
        try keychain.set(tokenResponse.refreshToken, forKey: KeychainManager.Key.syncRefreshToken)
        return tokenResponse.accessToken
    }

    private func serverURL() throws -> URL {
        if let rawValue = keychain.get(forKey: KeychainManager.Key.syncServerUrl),
           let url = URL(string: rawValue) {
            return url
        }
        if let defaultServerURL = configuration.mobileDefaultServerURL {
            return defaultServerURL
        }
        throw MobileAPIError.missingServerURL
    }

    private func decodeServerError(from data: Data, statusCode: Int) throws -> MobileAPIError {
        if statusCode == 401 {
            return .unauthorized
        }
        if let payload = try? decoder.decode(ServerErrorPayload.self, from: data),
           let message = payload.error?.message ?? payload.errorMessage {
            return .server(message)
        }
        return .server(HTTPURLResponse.localizedString(forStatusCode: statusCode))
    }
}

private struct EmptyPayload: Decodable {}

private struct MobileTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let scope: String
}

private struct ServerErrorPayload: Decodable {
    struct NestedError: Decodable {
        let message: String?
    }

    let error: NestedError?
    let errorMessage: String?
}

private extension URLComponents {
    static func formEncodedData(_ queryItems: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
