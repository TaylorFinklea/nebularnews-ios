import SwiftUI
import NebularNewsKit

// MARK: - Settings

struct CompanionSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @State private var settings: CompanionSettingsPayload?
    @State private var error: String?
    @State private var isLoading = true

    private static let pollIntervalRange = [5, 10, 15, 30, 60]
    private static let summaryStyles = ["concise", "detailed", "bullet"]
    private static let scoringMethods = ["ai", "algorithmic", "hybrid"]

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }

            if let settings {
                Section("Server") {
                    Picker("Poll interval", selection: pollIntervalBinding(settings)) {
                        ForEach(Self.pollIntervalRange, id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    Picker("Summary style", selection: summaryStyleBinding(settings)) {
                        ForEach(Self.summaryStyles, id: \.self) { style in
                            Text(style.capitalized).tag(style)
                        }
                    }
                    Picker("Scoring method", selection: scoringMethodBinding(settings)) {
                        ForEach(Self.scoringMethods, id: \.self) { method in
                            Text(method.capitalized).tag(method)
                        }
                    }
                }

                Section("News Brief") {
                    Toggle("Enabled", isOn: newsBriefEnabledBinding(settings))
                }
            }

            Section("Appearance") {
                @Bindable var tm = themeManager
                Picker("Theme", selection: $tm.mode) {
                    ForEach(ThemeManager.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("Connection") {
                LabeledContent("Server", value: appState.companionServerURL?.absoluteString ?? "Not connected")
                Button("Disconnect server", role: .destructive) {
                    appState.disconnectCompanion()
                }
            }
        }
        .navigationTitle("Settings")
        .overlay { if isLoading { ProgressView() } }
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        isLoading = true
        error = nil
        do {
            settings = try await appState.mobileAPI.fetchSettings()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ mutate: (inout CompanionSettingsPayload) -> Void) {
        guard var draft = settings else { return }
        mutate(&draft)
        settings = draft
        Task {
            do {
                settings = try await appState.mobileAPI.updateSettings(body: draft)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func pollIntervalBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.pollIntervalMinutes },
            set: { val in save { $0.pollIntervalMinutes = val } }
        )
    }

    private func summaryStyleBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.summaryStyle },
            set: { val in save { $0.summaryStyle = val } }
        )
    }

    private func scoringMethodBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.scoringMethod },
            set: { val in save { $0.scoringMethod = val } }
        )
    }

    private func newsBriefEnabledBinding(_ current: CompanionSettingsPayload) -> Binding<Bool> {
        Binding(
            get: { current.newsBriefConfig.enabled },
            set: { val in save { $0.newsBriefConfig.enabled = val } }
        )
    }
}
