import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var serverURLText = AppConfiguration.shared.mobileDefaultServerURL.absoluteString
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
                            .background(palette.surfaceStrong, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .background(palette.primarySoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .strokeBorder(palette.primary.opacity(0.18))
                            )

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
                Label("Connect to your server", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)

                TextField("Server URL", text: $serverURLText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

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
                        Text("Sign in")
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

        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host() != nil else {
            companionError = "Please enter a valid server URL."
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
