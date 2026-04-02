import SwiftUI
import NebularNewsKit

// MARK: - Advanced / Admin Settings

/// Platform-wide settings for server polling, AI scoring, and retention.
///
/// Accessed from ``ProfileView`` via the "Advanced Settings" link.
/// This will be gated behind an admin role check in a future update.
struct CompanionSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings: CompanionSettingsPayload?
    @State private var error: String?
    @State private var isLoading = true

    private static let pollIntervalRange = [5, 10, 15, 30, 60]
    private static let scoringMethods = ["ai", "algorithmic", "hybrid"]

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }

            if let settings {
                // MARK: - AI Configuration

                Section {
                    Picker("Scoring method", selection: scoringMethodBinding(settings)) {
                        ForEach(Self.scoringMethods, id: \.self) { method in
                            Text(method.capitalized).tag(method)
                        }
                    }
                } header: {
                    Label("AI Configuration", systemImage: "brain")
                } footer: {
                    Text("Controls how article relevance scores are computed.")
                }

                // MARK: - Feed Polling

                Section {
                    Picker("Poll interval", selection: pollIntervalBinding(settings)) {
                        ForEach(Self.pollIntervalRange, id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    HStack {
                        Text("Up Next articles")
                        Spacer()
                        TextField("6", value: upNextLimitBinding(settings), format: .number)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                } header: {
                    Label("Feed Polling", systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text("How often the server checks feeds for new articles.")
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
                    Text("Saved articles are never archived or deleted. Set 0 to disable.")
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .overlay { if isLoading && settings == nil { ProgressView() } }
        .task {
            await loadSettings()
        }
    }

    private func loadSettings() async {
        isLoading = true
        error = nil
        do {
            settings = try await appState.supabase.fetchSettings()
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
                settings = try await appState.supabase.updateSettings(draft)
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

    private func scoringMethodBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.scoringMethod },
            set: { val in save { $0.scoringMethod = val } }
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
