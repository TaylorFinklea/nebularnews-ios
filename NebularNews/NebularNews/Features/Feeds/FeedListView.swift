import SwiftUI
import SwiftData
import NebularNewsKit

struct FeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FeedListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                FeedListContent(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FeedListViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Content

private struct FeedListContent: View {
    @Bindable var viewModel: FeedListViewModel

    var body: some View {
        List {
            // Poll status banner
            if viewModel.isPolling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing feeds…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            } else if let message = viewModel.lastPollMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if viewModel.feeds.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Feeds",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Add an RSS feed to start reading.")
                )
            } else {
                ForEach(viewModel.feeds, id: \.id) { feed in
                    FeedRow(feed: feed)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteFeed(feed) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await viewModel.toggleEnabled(feed) }
                            } label: {
                                Label(
                                    feed.isEnabled ? "Disable" : "Enable",
                                    systemImage: feed.isEnabled ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(feed.isEnabled ? .orange : .green)
                        }
                }
            }
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await viewModel.refreshAllFeeds() }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isPolling)
            }
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddFeedSheet { feedUrl, title in
                Task {
                    let feed = try? await viewModel.feedRepo.add(feedUrl: feedUrl, title: title)
                    if let feed {
                        // Poll immediately for title auto-detection + first articles
                        await viewModel.pollSingleFeed(id: feed.id)
                    }
                    await viewModel.loadFeeds()
                }
            }
        }
        .task {
            await viewModel.loadFeeds()
        }
        .refreshable {
            await viewModel.refreshAllFeeds()
        }
    }
}

// MARK: - Feed Row

private struct FeedRow: View {
    let feed: Feed

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
                Text(feed.title.isEmpty ? feed.feedUrl : feed.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !feed.isEnabled {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let lastPolled = feed.lastPolledAt {
                        Text("Polled \(lastPolled.relativeDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never polled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = feed.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .help(error)
                    }
                }

                Text(feed.feedUrl)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(feed.articles?.count ?? 0)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .opacity(feed.isEnabled ? 1 : 0.6)
    }
}
