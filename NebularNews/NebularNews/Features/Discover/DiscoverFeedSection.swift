import SwiftUI
import SwiftData
import NebularNewsKit

/// Feed management section within the Discover tab.
struct DiscoverFeedSection: View {
    @Bindable var viewModel: FeedListViewModel

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
                                onToggle: { Task { await viewModel.toggleEnabled(feed) } },
                                onDelete: { Task { await viewModel.deleteFeed(feed) } }
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
    }
}

private struct DiscoverFeedRow: View {
    let feed: Feed
    let onToggle: () -> Void
    let onDelete: () -> Void

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
                    Text("\(feed.articles?.count ?? 0) articles")
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
