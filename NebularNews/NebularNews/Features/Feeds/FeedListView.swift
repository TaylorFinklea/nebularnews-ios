import SwiftUI
import NebularNewsKit

/// Feed list with add, delete, and navigate-to-articles functionality.
///
/// Ported from the standalone-era `FeedListView`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData.

private let feedPullWaitDuration: Duration = .seconds(3)

struct FeedListView: View {
    @Environment(AppState.self) private var appState

    @State private var feeds: [CompanionFeed] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showAddSheet = false
    @State private var newFeedURL = ""
    @State private var isPulling = false

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage) {
                    Task { await loadFeeds() }
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            // Pull status banner
            if isPulling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing feeds...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            if feeds.isEmpty && !isLoading && errorMessage.isEmpty {
                ContentUnavailableView(
                    "No Feeds",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Add an RSS feed to start reading.")
                )
            } else {
                ForEach(feeds) { feed in
                    NavigationLink {
                        ArticleListView(
                            feedId: feed.id,
                            feedTitle: feed.title.flatMap { $0.isEmpty ? nil : $0 } ?? feed.url
                        )
                    } label: {
                        FeedRow(feed: feed)
                    }
                }
                .onDelete(perform: deleteFeeds)
            }
        }
        .navigationTitle("Feeds")
        .overlay {
            if isLoading && feeds.isEmpty {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFeedURL = ""
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(isPulling)
            }
        }
        .alert("Add Feed", isPresented: $showAddSheet) {
            TextField("Feed URL", text: $newFeedURL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button("Add") { Task { await addFeed() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the URL of an RSS or Atom feed.")
        }
        .refreshable { await loadFeeds() }
        .task {
            if feeds.isEmpty {
                await loadFeeds()
            }
        }
    }

    private func loadFeeds() async {
        isLoading = true
        errorMessage = ""
        do {
            feeds = try await appState.supabase.fetchFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addFeed() async {
        let trimmed = newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await appState.supabase.addFeed(url: trimmed)
            await loadFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFeeds(at offsets: IndexSet) {
        let toDelete = offsets.map { feeds[$0] }
        Task {
            for feed in toDelete {
                do {
                    try await appState.supabase.deleteFeed(id: feed.id)
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
            await loadFeeds()
        }
    }

    private func refreshAll() async {
        isPulling = true
        do {
            try await appState.supabase.triggerPull()
            // Wait briefly for the pull to process, then reload
            try? await Task.sleep(for: feedPullWaitDuration)
            await loadFeeds()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPulling = false
    }
}

// MARK: - Feed Row

private struct FeedRow: View {
    let feed: CompanionFeed

    var body: some View {
        HStack(spacing: 12) {
            // Feed icon placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title.flatMap { $0.isEmpty ? nil : $0 } ?? feed.url)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if feed.disabled == 1 {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let lastPolled = feed.lastPolledAt {
                        Text("Polled \(relativeTime(lastPolled))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never polled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorCount = feed.errorCount, errorCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(feed.url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let count = feed.articleCount {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .opacity(feed.disabled == 1 ? 0.6 : 1)
    }

    private func relativeTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
