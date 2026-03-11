import SwiftUI
import SwiftData
import NebularNewsKit

/// Feed management section within the Discover tab.
struct DiscoverFeedSection: View {
    @Bindable var viewModel: FeedListViewModel
    @State private var presentedIssue: FeedIssuePresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your feeds")
                        .font(.headline)
                    Text("\(viewModel.feeds.count) source\(viewModel.feeds.count == 1 ? "" : "s") configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add Feed", systemImage: "plus") {
                    viewModel.showAddSheet = true
                }
                .buttonStyle(.bordered)
            }

            GroupBox {
                if viewModel.feeds.isEmpty {
                    ContentUnavailableView(
                        "No Feeds",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Add a feed to start building your reading universe.")
                    )
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.feeds.enumerated()), id: \.element.id) { index, feed in
                            DiscoverFeedRow(
                                feed: feed,
                                activeArticleCount: viewModel.activeArticleCount(for: feed.id),
                                onToggle: { Task { await viewModel.toggleEnabled(feed) } },
                                onDelete: { Task { await viewModel.deleteFeed(feed) } },
                                onShowIssue: {
                                    presentedIssue = FeedIssuePresentation(feed: feed)
                                },
                                onRetry: { Task { await viewModel.pollSingleFeed(id: feed.id) } }
                            )

                            if index < viewModel.feeds.count - 1 {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
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
    }
}

private struct DiscoverFeedRow: View {
    let feed: Feed
    let activeArticleCount: Int
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onShowIssue: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title.isEmpty ? feed.feedUrl : feed.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(activeArticleCount) articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !feed.isEnabled {
                        Text("Paused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    if feed.errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Toggle("Enabled", isOn: enabledBinding)
                .labelsHidden()

            Menu {
                if feed.errorMessage != nil {
                    Button {
                        onShowIssue()
                    } label: {
                        Label("View Issue", systemImage: "exclamationmark.bubble")
                    }

                    Button {
                        onRetry()
                    } label: {
                        Label("Retry Now", systemImage: "arrow.clockwise")
                    }
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { feed.isEnabled },
            set: { newValue in
                guard newValue != feed.isEnabled else { return }
                onToggle()
            }
        )
    }

    private var accentColor: Color {
        feed.isEnabled ? .cyan : .orange
    }
}

struct FeedIssuePresentation: Identifiable {
    let id: String
    let feedID: String
    let title: String
    let feedURL: String
    let errorMessage: String
    let lastPolledAt: Date?
    let consecutiveErrors: Int

    init?(feed: Feed) {
        guard let errorMessage = feed.errorMessage, !errorMessage.isEmpty else {
            return nil
        }

        id = feed.id
        feedID = feed.id
        title = feed.title.isEmpty ? feed.feedUrl : feed.title
        feedURL = feed.feedUrl
        self.errorMessage = errorMessage
        lastPolledAt = feed.lastPolledAt
        consecutiveErrors = feed.consecutiveErrors
    }
}

struct FeedIssueDetailsSheet: View {
    let issue: FeedIssuePresentation
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed") {
                    LabeledContent("Name") {
                        Text(issue.title)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("URL") {
                        Text(issue.feedURL)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    if let lastPolledAt = issue.lastPolledAt {
                        LabeledContent("Last polled") {
                            Text(lastPolledAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if issue.consecutiveErrors > 0 {
                        LabeledContent("Consecutive failures") {
                            Text("\(issue.consecutiveErrors)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Last Error") {
                    Text(issue.errorMessage)
                        .font(.body)
                        .textSelection(.enabled)
                }

                Section {
                    Button {
                        dismiss()
                        onRetry()
                    } label: {
                        Label("Retry Feed", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Feed Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
