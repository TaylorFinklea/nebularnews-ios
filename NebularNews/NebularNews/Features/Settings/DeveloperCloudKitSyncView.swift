#if DEBUG
import SwiftUI
import SwiftData
import NebularNewsKit

struct DeveloperCloudKitSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var snapshot: StandaloneSyncDebugSnapshot?
    @State private var isRefreshing = false
    @State private var isBootstrapping = false

    var body: some View {
        List {
            Section("Configuration") {
                LabeledContent("CloudKit", value: appState.configuration.cloudKitEnabled ? "Enabled" : "Disabled")
                LabeledContent("Container", value: appState.configuration.cloudKitContainerIdentifier ?? "None")
                LabeledContent("Mode", value: appState.isStandaloneMode ? "Standalone" : "Companion")
            }

            Section("Synced State") {
                if let snapshot {
                    LabeledContent("Feed subscriptions", value: "\(snapshot.syncedFeedSubscriptionCount)")
                    LabeledContent("Article states", value: "\(snapshot.syncedArticleStateCount)")
                    LabeledContent("Preferences", value: snapshot.syncedPreferences == nil ? "Missing" : "Present")
                } else {
                    loadingRow("Loading synced state…")
                }
            }

            Section("Synced Preferences") {
                if let preferences = snapshot?.syncedPreferences {
                    LabeledContent("Archive after", value: "\(preferences.archiveAfterDays) days")
                    LabeledContent("Delete archived after", value: "\(preferences.deleteArchivedAfterDays) days")
                    LabeledContent("Max articles per feed", value: "\(preferences.maxArticlesPerFeed)")
                    LabeledContent("Search archived", value: preferences.searchArchivedByDefault ? "On" : "Off")
                    LabeledContent("Updated", value: preferences.updatedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No synced preference record yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Local Projection") {
                if let snapshot {
                    LabeledContent("Local feeds", value: "\(snapshot.localFeedCount)")
                    LabeledContent("Local articles", value: "\(snapshot.localArticleCount)")
                    LabeledContent("Read", value: "\(snapshot.localReadCount)")
                    LabeledContent("Dismissed", value: "\(snapshot.localDismissedCount)")
                    LabeledContent("Reading List", value: "\(snapshot.localSavedCount)")
                    LabeledContent("Reacted", value: "\(snapshot.localReactedCount)")
                } else {
                    loadingRow("Loading local projection…")
                }
            }

            Section("Recent Feed Subscriptions") {
                if let snapshot, !snapshot.feedRows.isEmpty {
                    ForEach(snapshot.feedRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.titleOverride?.isEmpty == false ? row.titleOverride! : row.feedURL)
                                .font(.subheadline.weight(.semibold))
                            Text(row.feedURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(row.isEnabled ? "Enabled" : "Disabled")
                                Spacer()
                                Text(row.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No synced feed subscriptions yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recent Article States") {
                if let snapshot, !snapshot.articleStateRows.isEmpty {
                    ForEach(snapshot.articleStateRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.articleKey)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                            HStack(spacing: 12) {
                                Text(row.isRead ? "Read" : "Unread")
                                if row.isDismissed { Text("Dismissed") }
                                if row.isSaved { Text("Saved") }
                                if let reactionValue = row.reactionValue {
                                    Text("Reaction \(reactionValue)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(row.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("No synced article state rows yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task {
                        await bootstrapNow()
                    }
                } label: {
                    Label("Run Sync Bootstrap Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isRefreshing || isBootstrapping)
            } footer: {
                Text("Use this after changing devices or signing into iCloud to force a local projection pass without waiting for the next app lifecycle event.")
            }
        }
        .navigationTitle("CloudKit Sync")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshSnapshot()
        }
        .task {
            await refreshSnapshot()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshing || isBootstrapping {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshSnapshot() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let repo = LocalArticleRepository(modelContainer: modelContext.container)
        let snapshot = await repo.standaloneSyncDebugSnapshot()
        await MainActor.run {
            self.snapshot = snapshot
            isRefreshing = false
        }
    }

    private func bootstrapNow() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        let service = StandaloneStateSyncService(modelContainer: modelContext.container)
        await service.bootstrap()
        await refreshSnapshot()
        await MainActor.run {
            isBootstrapping = false
        }
    }
}
#endif
