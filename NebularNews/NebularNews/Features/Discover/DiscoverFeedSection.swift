import SwiftUI
import SwiftData
import NebularNewsKit

/// Feed management section within the Discover tab.
///
/// Shows a compact list of feeds with an add button.
/// Reuses `FeedListViewModel` and `AddFeedSheet` for feed operations.
struct DiscoverFeedSection: View {
    @Bindable var viewModel: FeedListViewModel

    var body: some View {
        DashboardSectionHeader(
            title: "Your feeds",
            subtitle: "\(viewModel.feeds.count) source\(viewModel.feeds.count == 1 ? "" : "s") configured."
        )

        ForEach(viewModel.feeds, id: \.id) { feed in
            DiscoverFeedCard(
                feed: feed,
                onToggle: { Task { await viewModel.toggleEnabled(feed) } },
                onDelete: { Task { await viewModel.deleteFeed(feed) } }
            )
        }

        Button {
            viewModel.showAddSheet = true
        } label: {
            GlassCard(cornerRadius: 18, style: .standard) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)

                    Text("Add feed")
                        .font(.headline)

                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feed Card

private struct DiscoverFeedCard: View {
    let feed: Feed
    let onToggle: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassCard(cornerRadius: 18, style: feed.isEnabled ? .raised : .standard, tintColor: accentColor) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(accentColor)
                            .font(.system(size: 15, weight: .semibold))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title.isEmpty ? feed.feedUrl : feed.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(feed.articles?.count ?? 0) articles")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !feed.isEnabled {
                            Text("Paused")
                                .font(.caption2.weight(.semibold))
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
            }
        }
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(
                    feed.isEnabled ? "Pause" : "Resume",
                    systemImage: feed.isEnabled ? "pause.circle" : "play.circle"
                )
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var accentColor: Color {
        feed.isEnabled ? .cyan : .orange
    }
}
