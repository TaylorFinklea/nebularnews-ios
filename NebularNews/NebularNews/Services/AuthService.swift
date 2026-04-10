import Foundation
import NebularNewsKit

/// Auth session returned by better-auth sign-in endpoints.
/// Matches the public interface of the former Supabase `Session` type
/// so callers like ProfileView can access `session.user.email`.
struct Session: Codable {
    let token: String
    let user: SessionUser
}

struct SessionUser: Codable {
    let id: String
    let email: String?
    let name: String?
    let image: String?
}

struct AuthService: Sendable {
    private let api = APIClient.shared

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        struct SignInBody: Encodable {
            let provider: String
            let idToken: String
            let nonce: String
        }

        let session: Session = try await api.request(
            method: "POST",
            path: "api/auth/sign-in/social",
            body: SignInBody(provider: "apple", idToken: idToken, nonce: nonce)
        )

        // Store the session token for subsequent authenticated requests
        api.sessionToken = session.token

        return session
    }

    func signOut() async throws {
        try await api.requestVoid(method: "POST", path: "api/auth/sign-out")
        api.sessionToken = nil
    }

    func session() async throws -> Session {
        // Validate current session with the server
        let session: Session = try await api.request(path: "api/auth/get-session")
        return session
    }

    func registerDeviceToken(token: String) async throws {
        struct Body: Encodable {
            let token: String
        }
        try await api.requestVoid(method: "POST", path: "api/devices/register", body: Body(token: token))
    }

    func removeDeviceToken(token: String) async throws {
        struct Body: Encodable {
            let token: String
        }
        try await api.requestVoid(method: "POST", path: "api/devices/remove", body: Body(token: token))
    }
}
