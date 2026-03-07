import SwiftUI
import SwiftData
import NebularNewsKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    @Query private var settingsResults: [AppSettings]

    private var settings: AppSettings {
        if let existing = settingsResults.first {
            return existing
        }
        // Create singleton on first access
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        try? modelContext.save()
        return newSettings
    }

    var body: some View {
        List {
            // MARK: - Feed Polling
            Section {
                Picker("Poll interval", selection: pollIntervalBinding) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("4 hours").tag(240)
                }

                Stepper(
                    "Max articles per feed: \(settings.maxArticlesPerFeed)",
                    value: maxArticlesBinding,
                    in: 10...200,
                    step: 10
                )

                Stepper(
                    "Retention: \(settings.retentionDays) days",
                    value: retentionBinding,
                    in: 7...365,
                    step: 7
                )
            } header: {
                Label("Feed Polling", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text("Background refresh runs approximately every poll interval. iOS may adjust timing based on usage patterns.")
            }

            // MARK: - AI Configuration
            Section {
                Picker("Default provider", selection: providerBinding) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI").tag("openai")
                }

                apiKeyRow(
                    label: "Anthropic API Key",
                    hasKey: appState.hasAnthropicKey,
                    provider: "anthropic"
                )

                apiKeyRow(
                    label: "OpenAI API Key",
                    hasKey: appState.hasOpenAIKey,
                    provider: "openai"
                )
            } header: {
                Label("AI Provider", systemImage: "brain")
            } footer: {
                Text("API keys are stored securely in your device Keychain and never synced to iCloud. In standalone mode, keys are only used for optional summaries and key points.")
            }

            // MARK: - Appearance
            Section {
                Picker("Appearance", selection: Bindable(themeManager).mode) {
                    ForEach(ThemeManager.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Appearance", systemImage: "paintbrush")
            } footer: {
                Text("System follows your device's light/dark mode setting.")
            }

            // MARK: - About
            Section {
                LabeledContent("Mode", value: appState.isCompanionMode ? "Companion" : "Standalone")
                LabeledContent("CloudKit", value: appState.configuration.cloudKitEnabled ? "Enabled" : "Disabled")

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .navigationTitle("Settings")
    }

    // MARK: - Bindings that auto-save

    private var pollIntervalBinding: Binding<Int> {
        Binding(
            get: { settings.pollIntervalMinutes },
            set: { newValue in
                settings.pollIntervalMinutes = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var maxArticlesBinding: Binding<Int> {
        Binding(
            get: { settings.maxArticlesPerFeed },
            set: { newValue in
                settings.maxArticlesPerFeed = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { settings.retentionDays },
            set: { newValue in
                settings.retentionDays = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { settings.defaultProvider },
            set: { newValue in
                settings.defaultProvider = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - API Key Row

    @ViewBuilder
    private func apiKeyRow(label: String, hasKey: Bool, provider: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if hasKey {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Not set")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
