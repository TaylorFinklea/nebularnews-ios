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
        NebularScreen {
            List {
                if viewModel.isPolling {
                    StatusBanner(
                        title: "Refreshing feeds",
                        detail: "Polling every enabled source and updating your local queue.",
                        systemImage: "arrow.clockwise",
                        accent: .cyan,
                        showProgress: true
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if let message = viewModel.lastPollMessage {
                    StatusBanner(
                        title: "Latest activity",
                        detail: message,
                        systemImage: "sparkles",
                        accent: .purple,
                        showProgress: false
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if viewModel.feeds.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Feeds",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Add a feed URL or import an OPML file to start reading.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.feeds, id: \.id) { feed in
                        NavigationLink {
                            ArticleListView(
                                feedId: feed.id,
                                feedTitle: feed.title.isEmpty ? feed.feedUrl : feed.title
                            )
                        } label: {
                            FeedRow(feed: feed)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            AddFeedSheet { request in
                switch request {
                case .single(let url, let title):
                    return await viewModel.addSingleFeed(feedUrl: url, title: title)
                case .opml(let entries):
                    return await viewModel.importOPMLFeeds(entries)
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

private struct StatusBanner: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color
    let showProgress: Bool

    var body: some View {
        GlassCard(cornerRadius: 24, style: .raised, tintColor: accent) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 42, height: 42)

                    if showProgress {
                        ProgressView()
                            .tint(accent)
                    } else {
                        Image(systemName: systemImage)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Feed Row

private struct FeedRow: View {
    let feed: Feed

    var body: some View {
        GlassCard(cornerRadius: 22, style: feed.isEnabled ? .raised : .standard, tintColor: accentColor) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(accentColor)
                            .font(.system(size: 17, weight: .semibold))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title.isEmpty ? feed.feedUrl : feed.title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if !feed.isEnabled {
                            Text("Paused")
                                .font(.caption.weight(.semibold))
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
                    .font(.headline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(accentColor.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(accentColor.opacity(0.16)))
            }
        }
    }

    private var accentColor: Color {
        feed.isEnabled ? .cyan : .orange
    }
}
