import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers
import NebularNewsKit
import os

// MARK: - Feeds

struct CompanionFeedsView: View {
    @Environment(AppState.self) private var appState
    private let logger = Logger(subsystem: "com.nebularnews", category: "CompanionFeedsView")

    @State private var feeds: [CompanionFeed] = []
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingAddFeed = false
    @State private var showingImport = false
    @State private var deletingFeed: CompanionFeed?
    @State private var editingFeed: CompanionFeed?
    /// The conflict action currently being presented in the conflict sheet.
    @State private var conflictAction: PendingAction?

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage) {
                    Task { await loadFeeds() }
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            if feeds.isEmpty && !isLoading && errorMessage.isEmpty {
                ContentUnavailableView(
                    "No feeds",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Add an RSS feed to start reading.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(feeds) { feed in
                HStack(spacing: 12) {
                    Group {
                        switch feed.feedType {
                        case "email_newsletter":
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 16, height: 16)
                        case "web_clip":
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 16, height: 16)
                        default:
                            Circle()
                                .fill(feedStatusColor(feed))
                                .frame(width: 8, height: 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title?.isEmpty == false ? feed.title! : feed.url)
                            .font(.headline)

                        HStack(spacing: 8) {
                            if let articleCount = feed.articleCount {
                                Text("\(articleCount) articles")
                            }
                            if let lastPolled = feed.lastPolledAt {
                                Text("Updated \(relativeTime(lastPolled))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if feed.paused == true {
                            Label("Paused", systemImage: "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if feed.disabledBool {
                            Label("Disabled", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let errorCount = feed.errorCount, errorCount > 0 {
                            Label("\(errorCount) consecutive error\(errorCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if let mode = feed.scrapeMode, mode != "rss_only" {
                            let label = mode == "auto_fetch_on_empty" ? "Auto-fetch" : "Full page"
                            Label(label, systemImage: mode == "auto_fetch_on_empty" ? "arrow.down.circle" : "globe")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }

                        if appState.syncManager?.hasPendingAction(forResource: feed.id) == true {
                            Label("Syncing…", systemImage: "icloud.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .opacity(feed.paused == true ? 0.5 : 1.0)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deletingFeed = feed
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task {
                            let newPaused = !(feed.paused ?? false)
                            do {
                                if let sync = appState.syncManager {
                                    try await sync.updateFeedSettings(feedId: feed.id, paused: newPaused)
                                } else {
                                    try await appState.supabase.updateFeedSettings(feedId: feed.id, paused: newPaused)
                                }
                            } catch SyncManagerError.queuedOffline {
                                // Queued — UI will reflect once replay succeeds.
                            } catch {
                                logger.error("Failed to update paused state for feed \(feed.id): \(error.localizedDescription)")
                            }
                            await loadFeeds()
                        }
                    } label: {
                        Label(feed.paused == true ? "Resume" : "Pause", systemImage: feed.paused == true ? "play.fill" : "pause.fill")
                    }
                    .tint(feed.paused == true ? .green : .orange)
                }
                .contextMenu {
                    Button {
                        editingFeed = feed
                    } label: {
                        Label("Feed Settings", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        Task {
                            let newPaused = !(feed.paused ?? false)
                            do {
                                if let sync = appState.syncManager {
                                    try await sync.updateFeedSettings(feedId: feed.id, paused: newPaused)
                                } else {
                                    try await appState.supabase.updateFeedSettings(feedId: feed.id, paused: newPaused)
                                }
                            } catch SyncManagerError.queuedOffline {
                                // Queued — UI will reflect once replay succeeds.
                            } catch {
                                logger.error("Failed to update paused state for feed \(feed.id): \(error.localizedDescription)")
                            }
                            await loadFeeds()
                        }
                    } label: {
                        Label(feed.paused == true ? "Resume Feed" : "Pause Feed", systemImage: feed.paused == true ? "play.fill" : "pause.fill")
                    }
                    Button(role: .destructive) {
                        deletingFeed = feed
                    } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await exportOPML() }
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add feed")
                }
            }
        }
        .overlay {
            if isLoading && feeds.isEmpty {
                ProgressView("Loading feeds…")
            }
        }
        .task {
            if feeds.isEmpty {
                await loadFeeds()
            }
        }
        .refreshable { await loadFeeds() }
        .sheet(isPresented: $showingAddFeed) {
            CompanionAddFeedSheet { url, scrapeMode in
                Task {
                    do {
                        _ = try await appState.supabase.addFeed(url: url, scrapeMode: scrapeMode)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            CompanionOPMLImportSheet { xml in
                Task {
                    do {
                        _ = try await appState.supabase.importOPML(xml: xml)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert(
            "Delete Feed",
            isPresented: Binding(
                get: { deletingFeed != nil },
                set: { if !$0 { deletingFeed = nil } }
            ),
            presenting: deletingFeed
        ) { feed in
            Button("Delete", role: .destructive) {
                Task { await deleteFeed(feed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { feed in
            Text("Delete \"\(feed.title ?? feed.url)\" and all its exclusive articles?")
        }
        .sheet(item: $editingFeed) { feed in
            FeedSettingsSheet(feed: feed) {
                Task { await loadFeeds() }
            }
        }
        .sheet(item: $conflictAction) { action in
            FeedSettingsConflictSheet(
                action: action,
                feedTitle: feeds.first(where: { $0.id == action.articleId })?.title
            )
            .onDisappear {
                // After the conflict sheet dismisses check for more conflicts and reload.
                checkForPendingConflicts()
                Task { await loadFeeds() }
            }
        }
        .onAppear { checkForPendingConflicts() }
        .onChange(of: appState.feedConflicts.pendingFeedIds.count) { checkForPendingConflicts() }
    }

    /// Pops the first pending conflict feed id and resolves it to a `PendingAction`
    /// so the conflict sheet can be presented.
    private func checkForPendingConflicts() {
        guard conflictAction == nil else { return }
        guard let sync = appState.syncManager else { return }
        guard let feedId = appState.feedConflicts.pendingFeedIds.first else { return }
        let conflicts = sync.fetchConflictedActions()
        if let action = conflicts.first(where: { $0.articleId == feedId }) {
            conflictAction = action
        } else {
            // Action was already resolved elsewhere — clear the notification.
            appState.feedConflicts.resolved(feedId: feedId)
        }
    }

    private func feedStatusColor(_ feed: CompanionFeed) -> Color {
        if feed.paused == true { return .orange }
        if feed.disabledBool { return .gray }
        if let errorCount = feed.errorCount, errorCount >= 3 { return .red }
        if let errorCount = feed.errorCount, errorCount > 0 { return .yellow }
        return .green
    }

    private func relativeTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func loadFeeds() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await appState.supabase.fetchFeeds()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFeed(_ feed: CompanionFeed) async {
        do {
            try await appState.supabase.deleteFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportOPML() async {
        do {
            let xml = try await appState.supabase.exportOPML()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("nebular-news.opml")
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                #if os(iOS)
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else { return }
                rootVC.present(activityVC, animated: true)
                #elseif os(macOS)
                let picker = NSSharingServicePicker(items: [tempURL])
                guard let window = NSApplication.shared.keyWindow,
                      let contentView = window.contentView else { return }
                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                #endif
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Feed Sheet

private struct CompanionAddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String, String?) -> Void
    @State private var url = ""

    private var normalized: FeedURLNormalized {
        FeedURLNormalizer.normalize(url)
    }

    private var isEmpty: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $url)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                } footer: {
                    if let label = normalized.sourceLabel, !isEmpty {
                        Label(label, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    } else {
                        Text("Paste an RSS, Atom, or source URL. Reddit, YouTube, Mastodon, and Hacker News URLs are normalized automatically.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(normalized.url, normalized.scrapeMode)
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - OPML Import Sheet

private struct CompanionOPMLImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (String) -> Void
    @State private var showingFilePicker = false
    @State private var importedXML: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("OPML document")
                Text("Select an OPML file to import feeds.")
                    .foregroundStyle(.secondary)
                Button("Choose File") {
                    showingFilePicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Import OPML")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.xml, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let xml = try? String(contentsOf: url, encoding: .utf8) {
                    onImport(xml)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Feed Settings Sheet

private struct FeedSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let feed: CompanionFeed
    let onSave: () -> Void

    @State private var paused: Bool
    @State private var maxArticlesPerDay: String
    @State private var minScore: Int
    @State private var scrapeMode: String
    @State private var scrapeProvider: String
    @State private var feedType: String
    @State private var isSaving = false

    /// ETag captured at sheet-open time, computed from the feed's current
    /// subscription values. Sent as `If-Match` on save to detect concurrent
    /// edits by another device. Per spec, we do NOT re-fetch on save — if the
    /// etag is stale the server 412s and the conflict sheet handles it.
    @State private var capturedEtag: String

    init(feed: CompanionFeed, onSave: @escaping () -> Void) {
        self.feed = feed
        self.onSave = onSave
        _paused = State(initialValue: feed.paused ?? false)
        _maxArticlesPerDay = State(initialValue: feed.maxArticlesPerDay.map { String($0) } ?? "")
        _minScore = State(initialValue: feed.minScore ?? 0)
        _scrapeMode = State(initialValue: feed.scrapeMode ?? "rss_only")
        _scrapeProvider = State(initialValue: feed.scrapeProvider ?? "")
        _feedType = State(initialValue: feed.feedType ?? "standard")
        // Compute ETag from the source feed values, not the displayed @State values,
        // so we capture what the server currently has (before the user edits).
        _capturedEtag = State(initialValue: feed.settingsEtag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Paused", isOn: $paused)
                } header: {
                    Text("Status")
                } footer: {
                    Text("Paused feeds stay subscribed but their articles are hidden until you resume.")
                }

                Section {
                    HStack {
                        Text("Max articles per day")
                        Spacer()
                        TextField("Unlimited", text: $maxArticlesPerDay)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } footer: {
                    Text("Limit how many articles you see from this feed per day. Leave blank for unlimited.")
                }

                Section {
                    Picker("Minimum score", selection: $minScore) {
                        Text("Any").tag(0)
                        Text("1+").tag(1)
                        Text("2+").tag(2)
                        Text("3+").tag(3)
                        Text("4+").tag(4)
                        Text("5 only").tag(5)
                    }
                } footer: {
                    Text("Only show articles from this feed that meet the minimum score threshold.")
                }

                Section {
                    Picker("Scrape mode", selection: $scrapeMode) {
                        Text("RSS Only").tag("rss_only")
                        Text("Auto-fetch when empty").tag("auto_fetch_on_empty")
                        Text("Always fetch full page").tag("always")
                    }

                    if scrapeMode != "rss_only" {
                        Picker("Provider", selection: $scrapeProvider) {
                            Text("Auto").tag("")
                            Text("Steel").tag("steel")
                            Text("Browserless").tag("browserless")
                        }
                    }
                } header: {
                    Text("Content Extraction")
                } footer: {
                    switch scrapeMode {
                    case "auto_fetch_on_empty":
                        Text("Fetches the full article when the feed only delivers a title and link — ideal for Anthropic, subreddits, and link-aggregators.")
                    case "always":
                        Text("Always fetches and extracts the full article even when RSS has content. Most thorough, highest cost.")
                    default:
                        Text("Uses only the content provided in the RSS feed. Choose 'Auto-fetch when empty' if articles are showing no content.")
                    }
                }

                if (feed.avgExtractionQuality ?? 0) > 0 || (feed.scrapeArticleCount ?? 0) > 0 {
                    Section("Extraction Stats") {
                        if let quality = feed.avgExtractionQuality, quality > 0 {
                            LabeledContent("Avg quality", value: "\(Int(quality * 100))%")
                        }
                        if let count = feed.scrapeArticleCount, count > 0 {
                            LabeledContent("Scraped articles", value: "\(count)")
                        }
                        if let errors = feed.scrapeErrorCount, errors > 0 {
                            LabeledContent("Errors", value: "\(errors)")
                        }
                        if let lastError = feed.lastScrapeError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(feed.title ?? "Feed Settings")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let maxPerDay = Int(maxArticlesPerDay) ?? 0
        do {
            if let sync = appState.syncManager {
                try await sync.updateFeedSettings(
                    feedId: feed.id,
                    paused: paused,
                    maxArticlesPerDay: maxPerDay,
                    minScore: minScore,
                    ifMatch: capturedEtag
                )
            } else {
                _ = try await appState.supabase.updateFeedSettings(
                    feedId: feed.id,
                    paused: paused,
                    maxArticlesPerDay: maxPerDay,
                    minScore: minScore,
                    ifMatch: capturedEtag
                )
            }
        } catch SyncManagerError.queuedOffline {
            // Queued for replay — dismiss normally.
        } catch let APIError.preconditionFailed(serverEtag, _) {
            // Live-save path got a 412 — park as conflict and surface the sheet.
            // The SyncManager queueConflict method handles the queue insertion,
            // snapshot fetch, and feedConflicts.notify.
            appState.syncManager?.queueConflict(
                feedId: feed.id,
                paused: paused,
                maxArticlesPerDay: maxPerDay,
                minScore: minScore,
                ifMatch: capturedEtag,
                serverEtag: serverEtag
            )
            // Dismiss this sheet; the conflict sheet will present via feedConflicts.
            onSave()
            dismiss()
            return
        } catch {
            // Best-effort — surfacing an alert here would break the dismiss flow.
        }

        if scrapeMode != (feed.scrapeMode ?? "rss_only") {
            try? await appState.supabase.updateScrapeMode(feedId: feed.id, scrapeMode: scrapeMode)
        }

        onSave()
        dismiss()
    }
}
