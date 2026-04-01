import Auth
import SwiftUI

/// User-facing profile and preferences screen.
///
/// Separates personal settings (appearance, reading, notifications, account)
/// from platform-wide admin settings which remain in ``CompanionSettingsView``.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var settings: CompanionSettingsPayload?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var userEmail: String?

    private static let summaryStyles = ["concise", "detailed", "bullet"]

    var body: some View {
        List {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            // MARK: - Appearance

            Section {
                @Bindable var tm = themeManager
                Picker("Theme", selection: $tm.mode) {
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

            // MARK: - Reading

            if let settings {
                Section {
                    Picker("Summary style", selection: summaryStyleBinding(settings)) {
                        ForEach(Self.summaryStyles, id: \.self) { style in
                            Text(style.capitalized).tag(style)
                        }
                    }
                } header: {
                    Label("Reading", systemImage: "book")
                } footer: {
                    Text("Controls the format of AI-generated article summaries.")
                }

                // MARK: - Notifications

                Section {
                    Toggle("News brief", isOn: newsBriefEnabledBinding(settings))
                    if settings.newsBriefConfig.enabled {
                        HStack {
                            Text("Timezone")
                            Spacer()
                            Text(settings.newsBriefConfig.timezone)
                                .foregroundStyle(.secondary)
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
                        Stepper(
                            "Lookback \(settings.newsBriefConfig.lookbackHours)h",
                            value: lookbackHoursBinding(settings),
                            in: 1...48
                        )
                        Stepper(
                            "Min score \(settings.newsBriefConfig.scoreCutoff)",
                            value: scoreCutoffBinding(settings),
                            in: 0...10
                        )
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                } footer: {
                    Text("Notification digests are sent at the configured times. Use HH:mm format.")
                }
            }

            // MARK: - Account

            Section {
                if let email = userEmail {
                    LabeledContent("Email", value: email)
                }
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            }

            // MARK: - Advanced

            Section {
                NavigationLink("Advanced Settings") {
                    CompanionSettingsView()
                }
            } footer: {
                Text("Server polling, retention, and scoring configuration.")
            }
        }
        .navigationTitle("Profile")
        .overlay { if isLoading && settings == nil { ProgressView() } }
        .task {
            await loadInitialData()
        }
    }

    // MARK: - Data

    private func loadInitialData() async {
        isLoading = true
        errorMessage = nil

        // Load user email from Supabase session
        if let session = try? await appState.supabase.session() {
            userEmail = session.user.email
        }

        // Load settings
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

    private func summaryStyleBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.summaryStyle },
            set: { val in save { $0.summaryStyle = val } }
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

    private func lookbackHoursBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.newsBriefConfig.lookbackHours },
            set: { val in save { $0.newsBriefConfig.lookbackHours = val } }
        )
    }

    private func scoreCutoffBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.newsBriefConfig.scoreCutoff },
            set: { val in save { $0.newsBriefConfig.scoreCutoff = val } }
        )
    }
}
