import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct MobileOAuthSession {
    let serverURL: URL
    let accessToken: String
    let refreshToken: String
    let scope: String
}

enum MobileOAuthError: LocalizedError {
    case invalidServerURL
    case invalidRedirectURI
    case authorizationCancelled
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The server URL is invalid."
        case .invalidRedirectURI:
            return "The OAuth redirect URI is invalid."
        case .authorizationCancelled:
            return "Sign-in was cancelled."
        case .invalidCallback:
            return "The OAuth callback could not be validated."
        case .stateMismatch:
            return "The OAuth state did not match."
        case .missingAuthorizationCode:
            return "The OAuth callback did not include an authorization code."
        case .invalidTokenResponse:
            return "The server returned an invalid OAuth token response."
        }
    }
}

@MainActor
final class MobileOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: AppConfiguration
    private var currentSession: ASWebAuthenticationSession?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func signIn(serverURL: URL) async throws -> MobileOAuthSession {
        guard let normalizedServerURL = normalizedServerURL(from: serverURL) else {
            throw MobileOAuthError.invalidServerURL
        }
        guard let redirectScheme = configuration.mobileOAuthRedirectURI.scheme else {
            throw MobileOAuthError.invalidRedirectURI
        }

        let state = randomURLSafeString()
        let codeVerifier = randomURLSafeString(length: 64)
        let codeChallenge = sha256Base64URL(codeVerifier)
        let resource = normalizedServerURL.appending(path: "api/mobile").absoluteString

        var components = URLComponents(url: normalizedServerURL.appending(path: "oauth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.mobileOAuthClientId),
            URLQueryItem(name: "redirect_uri", value: configuration.mobileOAuthRedirectURI.absoluteString),
            URLQueryItem(name: "scope", value: "app:read app:write"),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authorizeURL = components?.url else {
            throw MobileOAuthError.invalidServerURL
        }

        let callbackURL = try await startAuthorizationSession(url: authorizeURL, callbackURLScheme: redirectScheme)
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw MobileOAuthError.invalidCallback
        }
        let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value
        if returnedState != state {
            throw MobileOAuthError.stateMismatch
        }
        guard let code, !code.isEmpty else {
            throw MobileOAuthError.missingAuthorizationCode
        }

        return try await exchangeCode(
            serverURL: normalizedServerURL,
            code: code,
            codeVerifier: codeVerifier,
            resource: resource
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func startAuthorizationSession(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
                self.currentSession = nil
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: MobileOAuthError.authorizationCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: MobileOAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            session.start()
        }
    }

    private func exchangeCode(
        serverURL: URL,
        code: String,
        codeVerifier: String,
        resource: String
    ) async throws -> MobileOAuthSession {
        var request = URLRequest(url: serverURL.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLComponents.formEncodedData([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: configuration.mobileOAuthClientId),
            URLQueryItem(name: "redirect_uri", value: configuration.mobileOAuthRedirectURI.absoluteString),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "resource", value: resource)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw MobileOAuthError.invalidTokenResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(MobileTokenResponse.self, from: data)
        guard !payload.accessToken.isEmpty, !payload.refreshToken.isEmpty else {
            throw MobileOAuthError.invalidTokenResponse
        }
        return MobileOAuthSession(
            serverURL: serverURL,
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            scope: payload.scope
        )
    }

    private func normalizedServerURL(from inputURL: URL) -> URL? {
        guard var components = URLComponents(url: inputURL, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme == "https" || components.scheme == "http" else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct MobileTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let scope: String
}

private extension URLComponents {
    static func formEncodedData(_ queryItems: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

private func randomURLSafeString(length: Int = 32) -> String {
    let data = Data((0..<length).map { _ in UInt8.random(in: .min ... .max) })
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func sha256Base64URL(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return Data(digest).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
