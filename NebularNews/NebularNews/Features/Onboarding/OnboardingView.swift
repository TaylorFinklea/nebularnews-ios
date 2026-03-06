import SwiftUI
import NebularNewsKit

/// First-launch experience: welcome, add a feed, optionally enter AI key.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0
    @State private var feedUrl = ""
    @State private var apiKey = ""
    @State private var selectedProvider = "anthropic"

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome
            welcomePage
                .tag(0)

            // Page 2: Add your first feed
            addFeedPage
                .tag(1)

            // Page 3: AI setup (optional)
            aiSetupPage
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Nebular News")
                .font(.largeTitle.bold())

            Text("Your intelligent news reader.\nAI-powered scoring, summaries, and tagging\nfor the feeds you care about.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Get Started") {
                withAnimation { currentPage = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
                .frame(height: 60)
        }
        .padding(.horizontal, 32)
    }

    private var addFeedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Add Your First Feed")
                .font(.title2.bold())

            Text("Paste an RSS, Atom, or JSON Feed URL to get started.")
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
                Button("Skip") {
                    withAnimation { currentPage = 2 }
                }
                .buttonStyle(.bordered)

                Button("Add Feed") {
                    Task {
                        let repo = LocalFeedRepository(modelContainer: modelContext.container)
                        let url = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !url.isEmpty {
                            _ = try? await repo.add(feedUrl: url, title: "")
                        }
                        withAnimation { currentPage = 2 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)

            Spacer()
                .frame(height: 60)
        }
        .padding(.horizontal, 32)
    }

    private var aiSetupPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("AI Features (Optional)")
                .font(.title2.bold())

            Text("Enter an API key to enable AI summaries, scoring, and chat. You can always add this later in Settings.")
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
                Button("Skip") {
                    completeOnboarding()
                }
                .buttonStyle(.bordered)

                Button("Save & Continue") {
                    saveApiKey()
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)

            Spacer()
                .frame(height: 60)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func saveApiKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        let keychainKey = selectedProvider == "anthropic"
            ? KeychainManager.Key.anthropicApiKey
            : KeychainManager.Key.openaiApiKey

        try? appState.keychain.set(key, forKey: keychainKey)
    }

    private func completeOnboarding() {
        appState.hasCompletedOnboarding = true
    }
}
