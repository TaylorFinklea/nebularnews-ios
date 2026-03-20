import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var companionServerURL = AppConfiguration.shared.mobileDefaultServerURL?.absoluteString ?? "https://api.example.com"
    @State private var companionError = ""
    @State private var companionLoading = false

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
                            .frame(width: 96, height: 96)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .background(palette.primarySoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .strokeBorder(palette.primary.opacity(0.18))
                            )
                            .background {
                                NebularHeaderHalo(color: palette.primary)
                            }

                        Text("Nebular News")
                            .font(.largeTitle.bold())
                            .tracking(-0.8)

                        Text("Connect to your Nebular News server to get started. Sign in once and read the same dashboard, News Brief, articles, reactions, and tags as the web app.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    companionCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private var companionCard: some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: palette.primary) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Connect to a Nebular News server", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)

                TextField("https://api.example.com", text: $companionServerURL)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !companionError.isEmpty {
                    Text(companionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await connectCompanionMode() }
                } label: {
                    if companionLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in to server")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(companionLoading)
            }
        }
    }

    private func connectCompanionMode() async {
        companionLoading = true
        companionError = ""
        defer { companionLoading = false }

        let trimmed = companionServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            companionError = "Enter a valid server URL."
            return
        }

        do {
            let session = try await appState.mobileOAuthCoordinator.signIn(serverURL: url)
            try appState.completeCompanionOnboarding(
                serverURL: session.serverURL,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        } catch {
            companionError = error.localizedDescription
        }
    }
}
