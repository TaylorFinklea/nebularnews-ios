import SwiftUI
import NebularNewsKit

/// Settings view with server settings, appearance theme picker, and account.
///
/// Ported from the standalone-era `SettingsView`, now backed by
/// Supabase via `appState.supabase` for server settings.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var settings: CompanionSettingsPayload?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private static let pollIntervalRange = [5, 10, 15, 30, 60]
    private static let summaryStyles = ["concise", "detailed", "bullet"]
    private static let scoringMethods = ["ai", "algorithmic", "hybrid"]

    var body: some View {
        List {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if let settings {
                // MARK: - Server Settings
                Section {
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
                } header: {
                    Label("Server", systemImage: "server.rack")
                } footer: {
                    Text("Controls how the server processes new articles from your feeds.")
                }

                // MARK: - Retention
                Section {
                    HStack {
                        Text("Archive after")
                        Spacer()
                        TextField("30", value: retentionArchiveDaysBinding(settings), format: .number)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Delete after")
                        Spacer()
                        TextField("90", value: retentionDeleteDaysBinding(settings), format: .number)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Retention", systemImage: "clock.arrow.circlepath")
                } footer: {
                    Text("Saved articles are never archived or deleted.")
                }

                // MARK: - News Brief
                Section {
                    Toggle("Enabled", isOn: newsBriefEnabledBinding(settings))
                    Picker("Timezone", selection: timezoneBinding(settings)) {
                        ForEach(BriefTimezoneOptions.all, id: \.self) { id in
                            Text(BriefTimezoneOptions.label(for: id)).tag(id)
                        }
                    }
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
                } header: {
                    Label("News Brief", systemImage: "newspaper")
                } footer: {
                    Text("Notification digests fire at these local times in the selected timezone.")
                }
                .onAppear {
                    // Soft default: if the stored timezone is the baked-in UTC
                    // default but the device is somewhere else, nudge to the
                    // device zone so the cron fires at local time by default.
                    if settings.newsBriefConfig.timezone == "UTC" {
                        let device = TimeZone.current.identifier
                        if device != "UTC" {
                            save { $0.newsBriefConfig.timezone = device }
                        }
                    }
                }
            }

            // MARK: - Appearance
            Section {
                @Bindable var tm = themeManager
                Picker("Appearance", selection: $tm.mode) {
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
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }

            // MARK: - Account
            Section("Account") {
                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
            }
        }
        .navigationTitle("Settings")
        .overlay { if isLoading && settings == nil { ProgressView() } }
        .task {
            await loadSettings()
        }
    }

    // MARK: - Data

    private func loadSettings() async {
        isLoading = true
        errorMessage = nil
        do {
            settings = try await appState.supabase.fetchSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ mutate: (inout CompanionSettingsPayload) -> Void) {
        guard var draft = settings else { return }
        mutate(&draft)
        settings = draft
        Task {
            do {
                settings = try await appState.supabase.updateSettings(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Bindings

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

    private func timezoneBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.newsBriefConfig.timezone },
            set: { val in save { $0.newsBriefConfig.timezone = val } }
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
