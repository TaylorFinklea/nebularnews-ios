import Foundation
import Supabase

struct AuthService: Sendable {
    let client: SupabaseClient

    private var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func session() async throws -> Session {
        try await client.auth.session
    }

    func registerDeviceToken(token: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("device_tokens")
            .upsert(DeviceTokenUpsert(userId: userId.uuidString, token: token, platform: "ios"), onConflict: "token")
            .execute()
    }

    func removeDeviceToken(token: String) async throws {
        try await client.from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }
}
