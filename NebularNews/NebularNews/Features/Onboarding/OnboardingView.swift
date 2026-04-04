import SwiftUI
import AuthenticationServices
import CryptoKit

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var signInError = ""
    @State private var signInLoading = false
    @State private var currentNonce: String?

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NebularScreen(emphasis: .hero) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 56)

                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .frame(width: DesignTokens.onboardingIconSize, height: DesignTokens.onboardingIconSize)
                            .background(palette.surfaceStrong, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .background(palette.primarySoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .strokeBorder(palette.primary.opacity(0.18))
                            )

                        Text("Nebular News")
                            .font(.largeTitle.bold())
                            .tracking(-0.8)

                        Text("AI-powered RSS reader with personalized scoring, summaries, and News Briefs. Sign in with Apple to get started.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    signInCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private var signInCard: some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: palette.primary) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Sign in to continue", systemImage: "person.crop.circle")
                    .font(.headline)

                if !signInError.isEmpty {
                    Text(signInError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if signInLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = randomNonce()
                        currentNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = sha256Hash(nonce)
                    } onCompletion: { result in
                        Task { await handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        signInLoading = true
        signInError = ""
        defer { signInLoading = false }

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleIDCredential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                signInError = "Could not retrieve Apple ID token."
                return
            }

            do {
                _ = try await appState.supabase.signInWithApple(idToken: idToken, nonce: nonce)
                appState.completeSignIn()
            } catch {
                signInError = error.localizedDescription
            }

        case .failure(let error):
            // Don't show error for user-cancelled
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            signInError = error.localizedDescription
        }
    }
}

// MARK: - Nonce helpers

private func randomNonce(length: Int = 32) -> String {
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length
    while remainingLength > 0 {
        let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        for random in randoms {
            if remainingLength == 0 { break }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }
    return result
}

private func sha256Hash(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
