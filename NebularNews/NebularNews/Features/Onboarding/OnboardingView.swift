import SwiftUI
import SwiftData
import NebularNewsKit

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0
    @State private var feedUrl = ""
    @State private var apiKey = ""
    @State private var selectedProvider = "anthropic"
    @State private var companionServerURL = AppConfiguration.shared.mobileDefaultServerURL?.absoluteString ?? "https://api.example.com"
    @State private var companionError = ""
    @State private var companionLoading = false

    var body: some View {
        TabView(selection: $currentPage) {
            welcomePage
                .tag(0)

            standaloneFeedPage
                .tag(1)

            standaloneAIPage
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Nebular News")
                    .font(.largeTitle.bold())

                Text("Choose how you want to use the app. Companion mode signs into your existing Nebular News server and keeps the iPhone app in sync with the web app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                companionCard
                standaloneCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect to existing Nebular News server", systemImage: "iphone.and.arrow.forward")
                .font(.headline)
            Text("Use the public API hostname for your deployment, sign in once, and read the same dashboard, News Brief, articles, reactions, and tags as the web app.")
                .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var standaloneCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Use standalone mode", systemImage: "internaldrive")
                .font(.headline)
            Text("Run feeds, local polling, and optional provider keys directly on the device. This stays available, but companion mode is the primary production path.")
                .foregroundStyle(.secondary)
            Button("Set up standalone mode") {
                withAnimation { currentPage = 1 }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var standaloneFeedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Standalone feeds")
                .font(.title2.bold())

            Text("Add an RSS, Atom, or JSON Feed URL. You can also skip this and add feeds later.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("https://example.com/feed.xml", text: $feedUrl)
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation { currentPage = 0 }
                }
                .buttonStyle(.bordered)

                Button("Continue") {
                    Task {
                        let repo = LocalFeedRepository(modelContainer: modelContext.container)
                        let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            _ = try? await repo.add(feedUrl: trimmed, title: "")
                        }
                        withAnimation { currentPage = 2 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 32)
    }

    private var standaloneAIPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Standalone AI keys")
                .font(.title2.bold())

            Text("Provider keys are optional in standalone mode, stored locally on-device, and only used for summaries and key points.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Provider", selection: $selectedProvider) {
                Text("Anthropic").tag("anthropic")
                Text("OpenAI").tag("openai")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation { currentPage = 1 }
                }
                .buttonStyle(.bordered)

                Button("Finish standalone setup") {
                    if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? appState.saveStandaloneApiKey(provider: selectedProvider, key: apiKey)
                    }
                    appState.completeStandaloneOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            Button("Skip AI keys") {
                appState.completeStandaloneOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 32)
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
