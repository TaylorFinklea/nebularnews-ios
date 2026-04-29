import SwiftUI
import Combine
import os

/// Settings → Advanced → Sync queue
///
/// Shows the offline mutation queue: read-only pending items and an actionable
/// dead-letter (failed) section. Auto-refreshes every 5 seconds while open.
struct SyncQueueInspectorView: View {
    @Environment(AppState.self) private var appState

    @State private var pendingActions: [PendingAction] = []
    @State private var deadLetterActions: [PendingAction] = []
    @State private var pendingDescriptors: [SyncQueueRowDescriptor] = []
    @State private var deadLetterDescriptors: [SyncQueueRowDescriptor] = []

    /// Action being resolved (conflict diff sheet).
    @State private var resolvingAction: PendingAction?

    /// Offline-conflict alert: tapping a conflict row while offline shows this.
    @State private var showOfflineConflictAlert = false

    /// Bulk discard alert for dead-letter section.
    @State private var showBulkDiscardAlert = false

    /// Whether a retry is in-flight (disables rapid re-tap, spec edge case 7).
    @State private var isRetrying = false

    /// Timer publisher for the 5-second countdown refresh.
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private static let logger = Logger(subsystem: "com.nebularnews", category: "SyncQueueInspector")

    var body: some View {
        Group {
            if appState.syncManager == nil {
                queueNotReadyView
            } else if pendingDescriptors.isEmpty && deadLetterDescriptors.isEmpty {
                emptyStateView
            } else {
                queueList
            }
        }
        .navigationTitle("Sync queue")
        .inlineNavigationBarTitle()
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
            Self.logger.info("sync-queue-inspector opened pending=\(pendingActions.count) deadLetter=\(deadLetterActions.count)")
        }
        .onReceive(timer) { _ in
            refreshSync()
        }
        .alert("Connect to network", isPresented: $showOfflineConflictAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Connect to the internet to resolve conflicts.")
        }
        .alert("Discard all failed actions?", isPresented: $showBulkDiscardAlert) {
            Button("Discard \(deadLetterActions.count) actions", role: .destructive) {
                bulkDiscard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(deadLetterActions.count) actions will be permanently discarded. Their changes will not be applied.")
        }
        .sheet(item: $resolvingAction) { action in
            // Wire to FeedSettingsConflictSheet from feed-settings-conflict-spec.
            // The sheet needs a feedTitle — look it up from the cached feeds.
            let feedTitle: String? = {
                let feeds = appState.articleCache?.getCachedFeeds() ?? []
                return feeds.first(where: { $0.id == action.articleId })?.title
            }()
            FeedSettingsConflictSheet(action: action, feedTitle: feedTitle)
        }
    }

    // MARK: - Sub-views

    private var queueNotReadyView: some View {
        ContentUnavailableView(
            "Queue not ready yet",
            systemImage: "hourglass",
            description: Text("Try again in a moment.")
        )
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "All caught up",
            systemImage: "checkmark.icloud",
            description: Text("There's nothing waiting to sync. Edits you make offline will appear here until they reach the server.")
        )
    }

    private var queueList: some View {
        List {
            // MARK: Pending section
            if !pendingDescriptors.isEmpty {
                Section("Pending") {
                    ForEach(pendingDescriptors) { desc in
                        SyncQueuePendingRow(
                            descriptor: desc,
                            isOffline: appState.syncManager?.isOffline ?? false,
                            resolvingAction: $resolvingAction,
                            resolveAction: { id in
                                pendingActions.first(where: { $0.id == id })
                            }
                        )
                        .listRowSeparator(.visible)
                    }
                }
            }

            // MARK: Dead-letter section (only when non-empty)
            if !deadLetterDescriptors.isEmpty {
                Section {
                    ForEach(deadLetterDescriptors) { desc in
                        SyncQueueDeadLetterRow(
                            descriptor: desc,
                            onRetry: {
                                await retryDeadLetter(id: desc.id)
                            },
                            onDiscard: {
                                discardDeadLetter(id: desc.id)
                            },
                            onReport: {
                                // Report is handled inside the row itself via ShareLink+logging.
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("Needs attention")
                        Spacer()
                        if deadLetterDescriptors.count > 1 {
                            Button("Discard all") {
                                showBulkDiscardAlert = true
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            // MARK: About section (always present)
            Section {
                Text("Actions you take while offline are queued here. They sync automatically when you're back online. If an action fails 10 times it moves to Needs attention for manual triage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About this queue")
            }
        }
    }

    // MARK: - Data loading

    @MainActor
    private func refresh() async {
        guard let sync = appState.syncManager else { return }
        pendingActions = sync.fetchPendingActions()
        deadLetterActions = sync.fetchDeadLetterActions()
        rebuildDescriptors()
    }

    private func refreshSync() {
        guard let sync = appState.syncManager else { return }
        pendingActions = sync.fetchPendingActions()
        deadLetterActions = sync.fetchDeadLetterActions()
        rebuildDescriptors()
    }

    private func rebuildDescriptors() {
        guard let sync = appState.syncManager else { return }
        let cache = appState.articleCache

        let cachedFeeds = cache?.getCachedFeeds() ?? []
        let feedLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: cachedFeeds.compactMap { f in
                guard let title = f.title else { return nil }
                return (f.id, title)
            }
        )

        // Build a flat article lookup from cached articles (up to 1000).
        // This is best-effort: newly cached articles may not be in the list.
        let cachedArticles = cache?.getCachedArticles(limit: 1000) ?? []
        let articleLookup: [String: String] = Dictionary(
            uniqueKeysWithValues: cachedArticles.compactMap { a in
                guard let title = a.title else { return nil }
                return (a.id, title)
            }
        )

        // Deduplicate by id before building descriptors (spec edge case 6)
        var seenIds = Set<String>()
        let dedupedPending = pendingActions.filter { seenIds.insert($0.id).inserted }
        seenIds.removeAll()
        let dedupedDeadLetter = deadLetterActions.filter { seenIds.insert($0.id).inserted }

        pendingDescriptors = dedupedPending.map { action in
            SyncQueueRowDescriptor.from(
                action,
                cachedArticleTitle: { id in articleLookup[id] },
                cachedFeedTitle: { id in feedLookup[id] },
                isOffline: sync.isOffline
            )
        }

        deadLetterDescriptors = dedupedDeadLetter.map { action in
            SyncQueueRowDescriptor.from(
                action,
                cachedArticleTitle: { id in articleLookup[id] },
                cachedFeedTitle: { id in feedLookup[id] },
                isOffline: sync.isOffline
            )
        }
    }

    // MARK: - Actions

    @MainActor
    private func retryDeadLetter(id: String) async {
        guard !isRetrying else { return }
        guard let sync = appState.syncManager else { return }

        // Re-fetch by id to avoid stale-model crash (spec edge case 1)
        guard let action = deadLetterActions.first(where: { $0.id == id }) else {
            // Action already synced or discarded — no-op with informal notice.
            return
        }

        isRetrying = true
        sync.retryDeadLetter(action)
        await sync.syncPendingActions()
        isRetrying = false

        await refresh()
    }

    private func discardDeadLetter(id: String) {
        guard let sync = appState.syncManager else { return }

        // Re-fetch by id to avoid stale-model crash (spec edge case 1)
        guard let action = deadLetterActions.first(where: { $0.id == id }) else { return }

        sync.discardDeadLetter(action)
        refreshSync()
    }

    private func bulkDiscard() {
        guard let sync = appState.syncManager else { return }
        for action in deadLetterActions {
            sync.discardDeadLetter(action)
        }
        refreshSync()
    }
}
