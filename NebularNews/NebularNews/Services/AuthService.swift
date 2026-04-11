import Foundation
import NebularNewsKit

/// better-auth response for social sign-in.
struct BetterAuthResponse: Decodable {
    let session: BetterAuthSession
    let user: BetterAuthUser
}

struct BetterAuthSession: Decodable {
    let id: String
    let token: String
    let expiresAt: String?
}

struct BetterAuthUser: Decodable {
    let id: String
    let email: String?
    let name: String?
    let image: String?
}

/// Lightweight Session type matching the old Supabase `Session` interface.
struct Session {
    let token: String
    let user: SessionUser
}

struct SessionUser {
    let id: String
    let email: String?
    let name: String?
}

struct AuthService: Sendable {
    private let api = APIClient.shared

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        // better-auth expects idToken as an object, camelCase keys, no envelope
        let body: [String: Any] = [
            "provider": "apple",
            "callbackURL": "/",
            "idToken": [
                "token": idToken,
                "nonce": nonce
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var url = api.baseURL.appendingPathComponent("api/auth/sign-in/social")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, errorText)
        }

        // better-auth returns { session: { token, ... }, user: { id, email, ... } }
        let decoder = JSONDecoder()
        let authResponse = try decoder.decode(BetterAuthResponse.self, from: data)

        // Store the session token
        api.sessionToken = authResponse.session.token

        return Session(
            token: authResponse.session.token,
            user: SessionUser(
                id: authResponse.user.id,
                email: authResponse.user.email,
                name: authResponse.user.name
            )
        )
    }

    func signOut() async throws {
        // better-auth sign-out — also not envelope-wrapped
        var url = api.baseURL.appendingPathComponent("api/auth/sign-out")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = api.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _ = try await URLSession.shared.data(for: request)
        api.sessionToken = nil
    }

    func session() async throws -> Session {
        // better-auth get-session — returns { session: ..., user: ... } or null
        var url = api.baseURL.appendingPathComponent("api/auth/get-session")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = api.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            throw APIError.unauthorized
        }

        let decoder = JSONDecoder()
        let authResponse = try decoder.decode(BetterAuthResponse.self, from: data)

        return Session(
            token: authResponse.session.token,
            user: SessionUser(
                id: authResponse.user.id,
                email: authResponse.user.email,
                name: authResponse.user.name
            )
        )
    }

    func registerDeviceToken(token: String) async throws {
        struct Body: Encodable { let token: String }
        try await api.requestVoid(method: "POST", path: "api/devices/register", body: Body(token: token))
    }

    func removeDeviceToken(token: String) async throws {
        struct Body: Encodable { let token: String }
        try await api.requestVoid(method: "POST", path: "api/devices/remove", body: Body(token: token))
    }
}
