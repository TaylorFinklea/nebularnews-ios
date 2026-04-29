import SwiftUI
import os

// MARK: - Resolution types

/// Per-field choice in a conflict merge: keep the server value or keep the
/// local ("mine") value.
enum FeedSettingsFieldChoice: String, Codable, CaseIterable {
    case server
    case mine
}

/// The user's chosen resolution for all three mutable subscription fields.
struct FeedSettingsResolution {
    var paused: FeedSettingsFieldChoice
    var maxArticlesPerDay: FeedSettingsFieldChoice
    var minScore: FeedSettingsFieldChoice

    /// Adopt all server values — effectively discards the local edit.
    static let allServer = FeedSettingsResolution(
        paused: .server,
        maxArticlesPerDay: .server,
        minScore: .server
    )

    /// Apply all local ("mine") values.
    static let allMine = FeedSettingsResolution(
        paused: .mine,
        maxArticlesPerDay: .mine,
        minScore: .mine
    )
}

// MARK: - Conflict Sheet

/// Presented when a `feed_settings` action is parked with `state = "conflict"`
/// after a 412 Precondition Failed from the server.
///
/// Shows a per-field diff (Server / Mine) and lets the user pick:
/// - **Keep server** — adopt all server values
/// - **Apply mine** — apply all local values
/// - **Merge** — use the per-row pickers to choose field-by-field
///
/// When the server snapshot is unavailable the sheet falls back to a simpler
/// two-button layout (Keep server / Apply mine only).
struct FeedSettingsConflictSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let action: PendingAction
    let feedTitle: String?

    @State private var pausedChoice: FeedSettingsFieldChoice = .server
    @State private var maxChoice: FeedSettingsFieldChoice = .server
    @State private var minChoice: FeedSettingsFieldChoice = .server

    private let logger = Logger(subsystem: "com.nebularnews", category: "FeedSettingsConflictSheet")

    // MARK: - Decoded payloads

    private var minePayload: FeedSettingsPayload? {
        try? JSONDecoder().decode(FeedSettingsPayload.self, from: Data(action.payload.utf8))
    }

    private var serverPayload: FeedSettingsPayload? {
        guard let json = action.conflictServerSnapshotJSON else { return nil }
        return try? JSONDecoder().decode(FeedSettingsPayload.self, from: Data(json.utf8))
    }

    private var hasServerSnapshot: Bool { serverPayload != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if hasServerSnapshot {
                    fullMergeView
                } else {
                    simpleTwoButtonView
                }
            }
            .navigationTitle("Feed settings changed elsewhere")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.feedConflicts.resolved(feedId: action.articleId)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Full merge view (server snapshot available)

    private var fullMergeView: some View {
        let mine = minePayload
        let server = serverPayload

        return Form {
            Section {
                if let title = feedTitle {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Another device saved different settings for this feed. Choose which values to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Paused field
            if let minePaused = mine?.paused, let serverPaused = server?.paused {
                Section("Status (Paused)") {
                    conflictRow(
                        label: "Server",
                        value: serverPaused ? "Paused" : "Active",
                        isHighlighted: serverPaused != minePaused
                    )
                    conflictRow(
                        label: "Mine",
                        value: minePaused ? "Paused" : "Active",
                        isHighlighted: serverPaused != minePaused
                    )
                    Picker("Keep", selection: $pausedChoice) {
                        Text("Server").tag(FeedSettingsFieldChoice.server)
                        Text("Mine").tag(FeedSettingsFieldChoice.mine)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Max articles/day field
            Section("Daily Cap") {
                let serverMax = server?.maxArticlesPerDay
                let mineMax = mine?.maxArticlesPerDay
                conflictRow(
                    label: "Server",
                    value: serverMax.map { "\($0) articles/day" } ?? "Unlimited",
                    isHighlighted: serverMax != mineMax
                )
                conflictRow(
                    label: "Mine",
                    value: mineMax.map { "\($0) articles/day" } ?? "Unlimited",
                    isHighlighted: serverMax != mineMax
                )
                Picker("Keep", selection: $maxChoice) {
                    Text("Server").tag(FeedSettingsFieldChoice.server)
                    Text("Mine").tag(FeedSettingsFieldChoice.mine)
                }
                .pickerStyle(.segmented)
            }

            // Min score field
            Section("Minimum Score") {
                let serverMin = server?.minScore
                let mineMin = mine?.minScore
                conflictRow(
                    label: "Server",
                    value: scoreLabel(serverMin),
                    isHighlighted: serverMin != mineMin
                )
                conflictRow(
                    label: "Mine",
                    value: scoreLabel(mineMin),
                    isHighlighted: serverMin != mineMin
                )
                Picker("Keep", selection: $minChoice) {
                    Text("Server").tag(FeedSettingsFieldChoice.server)
                    Text("Mine").tag(FeedSettingsFieldChoice.mine)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Keep server") { submit(.allServer) }
                    .frame(maxWidth: .infinity)
                Button("Apply mine") { submit(.allMine) }
                    .frame(maxWidth: .infinity)
                Button("Merge") {
                    submit(FeedSettingsResolution(
                        paused: pausedChoice,
                        maxArticlesPerDay: maxChoice,
                        minScore: minChoice
                    ))
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            // Default: server wins for fields that differ from mine.
            if let mine, let server {
                pausedChoice = (mine.paused == server.paused) ? .mine : .server
                maxChoice = (mine.maxArticlesPerDay == server.maxArticlesPerDay) ? .mine : .server
                minChoice = (mine.minScore == server.minScore) ? .mine : .server
            }
        }
    }

    // MARK: - Simple two-button view (no server snapshot)

    private var simpleTwoButtonView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            if let title = feedTitle {
                Text(title)
                    .font(.headline)
            }

            Text("Feed settings were changed on another device while your change was pending.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Couldn't load current server values — pick a side and we'll sync.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)

            VStack(spacing: 12) {
                Button("Keep server") { submit(.allServer) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)

                Button("Apply mine") { submit(.allMine) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func conflictRow(label: String, value: String, isHighlighted: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
                .fontWeight(isHighlighted ? .semibold : .regular)
        }
    }

    private func scoreLabel(_ score: Int?) -> String {
        switch score {
        case nil: return "Any"
        case 0: return "Any"
        case 5: return "5 only"
        default: return "\(score!)+"
        }
    }

    private func submit(_ resolution: FeedSettingsResolution) {
        guard let sync = appState.syncManager else {
            appState.feedConflicts.resolved(feedId: action.articleId)
            dismiss()
            return
        }
        sync.resolveConflict(action, with: resolution)
        // feedConflicts.resolved is called inside resolveConflict
        dismiss()
    }
}
