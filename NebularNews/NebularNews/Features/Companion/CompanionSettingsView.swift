import SwiftUI
import NebularNewsKit

// MARK: - Settings

struct CompanionSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @State private var settings: CompanionSettingsPayload?
    @State private var error: String?
    @State private var isLoading = true
    @State private var serverURLDraft = ""
    @State private var isReconnecting = false

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
                    HStack {
                        Text("Up Next articles")
                        Spacer()
                        TextField("6", value: upNextLimitBinding(settings), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }

                Section("Retention") {
                    HStack {
                        Text("Archive after")
                        Spacer()
                        TextField("30", value: retentionArchiveDaysBinding(settings), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Delete after")
                        Spacer()
                        TextField("90", value: retentionDeleteDaysBinding(settings), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                    Text("Saved articles are never archived or deleted. 0 disables.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("News Brief & Notifications") {
                    Toggle("Enabled", isOn: newsBriefEnabledBinding(settings))
                    HStack {
                        Text("Morning")
                        Spacer()
                        TextField("08:00", text: morningTimeBinding(settings))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Evening")
                        Spacer()
                        TextField("17:00", text: eveningTimeBinding(settings))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                    Text("News briefs and notification digests are sent at these times. Use HH:mm format.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                TextField("Server URL", text: $serverURLDraft)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if serverURLDraft != (appState.companionServerURL?.absoluteString ?? "") {
                    Button("Reconnect to new server") {
                        Task { await reconnect() }
                    }
                    .disabled(isReconnecting)
                }
                Button("Disconnect server", role: .destructive) {
                    appState.disconnectCompanion()
                }
            }
        }
        .navigationTitle("Settings")
        .overlay { if isLoading { ProgressView() } }
        .task {
            serverURLDraft = appState.companionServerURL?.absoluteString ?? ""
            await loadSettings()
        }
    }

    private func reconnect() async {
        let trimmed = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            error = "Enter a valid server URL."
            return
        }
        isReconnecting = true
        defer { isReconnecting = false }
        do {
            appState.disconnectCompanion()
            let session = try await appState.mobileOAuthCoordinator.signIn(serverURL: url)
            try appState.completeCompanionOnboarding(
                serverURL: session.serverURL,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        } catch {
            self.error = error.localizedDescription
        }
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

    private func morningTimeBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.newsBriefConfig.morningTime },
            set: { val in save { $0.newsBriefConfig.morningTime = val } }
        )
    }

    private func eveningTimeBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.newsBriefConfig.eveningTime },
            set: { val in save { $0.newsBriefConfig.eveningTime = val } }
        )
    }

    private func upNextLimitBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.upNextLimit },
            set: { val in save { $0.upNextLimit = val } }
        )
    }

    private func retentionArchiveDaysBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.retentionArchiveDays ?? 30 },
            set: { val in save { $0.retentionArchiveDays = val } }
        )
    }

    private func retentionDeleteDaysBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.retentionDeleteDays ?? 90 },
            set: { val in save { $0.retentionDeleteDays = val } }
        )
    }
}
