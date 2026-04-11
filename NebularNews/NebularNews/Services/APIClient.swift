import Foundation
import NebularNewsKit
import os

// MARK: - API Client

/// Generic REST client for the Cloudflare Workers backend.
///
/// Replaces the Supabase SDK with plain URLSession calls against
/// a JSON envelope API (`{ "ok": true, "data": ... }`).
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let logger = Logger(subsystem: "com.nebularnews", category: "APIClient")
    private let keychain = KeychainManager(service: "com.nebularnews.ios")

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Don't convert to snake_case — Workers API accepts camelCase request bodies
        return e
    }()

    // MARK: - Configuration

    /// Base URL — configurable, stored in UserDefaults.
    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://api.nebularnews.com"
        return URL(string: stored)!
    }

    /// Session token from better-auth — stored in Keychain.
    var sessionToken: String? {
        get { keychain.get(forKey: "session_token") }
        set {
            if let v = newValue {
                try? keychain.set(v, forKey: "session_token")
            } else {
                keychain.delete(forKey: "session_token")
            }
        }
    }

    /// Whether the client currently has a stored session token.
    var hasSession: Bool {
        sessionToken != nil
    }

    // MARK: - Generic Request

    /// Make a request and decode the `data` field from the JSON envelope.
    func request<T: Decodable>(
        method: String = "GET",
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: body, queryItems: queryItems)
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        guard envelope.ok, let resultData = envelope.data else {
            throw APIError.serverError(0, envelope.error?.message ?? "Unknown error")
        }
        return resultData
    }

    /// Fire-and-forget request (no response body needed).
    func requestVoid(method: String = "POST", path: String, body: (any Encodable)? = nil, queryItems: [URLQueryItem]? = nil) async throws {
        let data = try await rawRequest(method: method, path: path, body: body, queryItems: queryItems)
        // Just validate the envelope is ok
        let envelope = try decoder.decode(APIEnvelopeBase.self, from: data)
        guard envelope.ok else {
            throw APIError.serverError(0, envelope.error?.message ?? "Unknown error")
        }
    }

    /// Raw request that returns the response Data (for cases where the response
    /// isn't wrapped in an envelope, like OPML export returning plain text).
    func rawRequest(
        method: String = "GET",
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        var url = baseURL.appendingPathComponent(path)
        if let queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems.filter { $0.value != nil }
            url = components.url!
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // BYOK headers
        let byokKeychain = KeychainManager(service: "com.nebularnews.ios")
        if let key = byokKeychain.get(forKey: KeychainManager.Key.anthropicApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("anthropic", forHTTPHeaderField: "x-user-api-provider")
        } else if let key = byokKeychain.get(forKey: KeychainManager.Key.openaiApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("openai", forHTTPHeaderField: "x-user-api-provider")
        }

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        logger.debug("[\(method)] \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            // Try to decode the error envelope
            if let errorBody = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(httpResponse.statusCode, errorBody.error.message)
            }
            throw APIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }

        return data
    }
}

// MARK: - Envelope Types

struct APIEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: APIErrorDetail?
}

struct APIEnvelopeBase: Decodable {
    let ok: Bool
    let error: APIErrorDetail?
}

struct APIErrorDetail: Decodable {
    let code: String?
    let message: String
}

struct APIErrorResponse: Decodable {
    let ok: Bool
    let error: APIErrorDetail
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case unauthorized
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Not authenticated"
        case .serverError(_, let msg): return msg
        }
    }
}

// MARK: - Type Erasure Helper

/// Wrapper to allow encoding any `Encodable` value through a generic parameter.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
