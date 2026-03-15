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
    @State private var presentedIssue: FeedIssuePresentation?

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
                    if !viewModel.lowestReputationFeeds.isEmpty {
                        Section("Lowest Reputation") {
                            ForEach(viewModel.lowestReputationFeeds.filter { $0.feedID != nil }, id: \.feedKey) { summary in
                                if let feedID = summary.feedID {
                                    NavigationLink {
                                        ArticleListView(feedId: feedID, feedTitle: summary.title)
                                    } label: {
                                        FeedReputationAdminRow(summary: summary)
                                    }
                                }
                            }
                        }
                    }

                    ForEach(viewModel.feeds, id: \.id) { feed in
                        NavigationLink {
                            ArticleListView(
                                feedId: feed.id,
                                feedTitle: feed.title.isEmpty ? feed.feedUrl : feed.title
                            )
                        } label: {
                            FeedRow(
                                feed: feed,
                                activeArticleCount: viewModel.activeArticleCount(for: feed.id),
                                reputation: viewModel.reputationSummary(for: feed.feedKey),
                                onShowIssue: {
                                    presentedIssue = FeedIssuePresentation(
                                        feed: feed,
                                        reputation: viewModel.reputationSummary(for: feed.feedKey)
                                    )
                                }
                            )
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
        .sheet(item: $presentedIssue) { issue in
            FeedIssueDetailsSheet(
                issue: issue,
                onRetry: {
                    Task { await viewModel.pollSingleFeed(id: issue.feedID) }
                }
            )
            .presentationDetents([.medium, .large])
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
        HStack(alignment: .top, spacing: 12) {
            if showProgress {
                ProgressView()
                    .tint(accent)
                    .padding(.top, 2)
            } else {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 20)
                    .padding(.top, 2)
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

// MARK: - Feed Row

private struct FeedRow: View {
    let feed: Feed
    let activeArticleCount: Int
    let reputation: FeedReputationSummary?
    let onShowIssue: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

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
                }

                if let reputation {
                    Text(reputationRowText(for: reputation))
                        .font(.caption)
                        .foregroundStyle(reputation.feedbackCount > 0 ? .secondary : .tertiary)
                        .lineLimit(1)
                }

                if let error = feed.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(feed.feedUrl)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(activeArticleCount)")
                    .font(.headline.bold())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let error = feed.errorMessage {
                    Button {
                        onShowIssue()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View feed issue")
                    .accessibilityHint(error)
                }
            }
        }
    }

    private var accentColor: Color {
        feed.isEnabled ? .cyan : .orange
    }
}

private struct FeedReputationAdminRow: View {
    let summary: FeedReputationSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.thumbsup")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(summary.feedURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Text(reputationRowText(for: summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private func reputationRowText(for summary: FeedReputationSummary) -> String {
    guard summary.feedbackCount > 0 else {
        return "No trust data yet"
    }
    return "Reputation \(reputationScoreText(summary.score)) · \(reputationVoteText(summary.feedbackCount))"
}

private func reputationScoreText(_ score: Double) -> String {
    String(format: "%.2f", score)
}

private func reputationVoteText(_ feedbackCount: Int) -> String {
    "\(feedbackCount) trust vote\(feedbackCount == 1 ? "" : "s")"
}
