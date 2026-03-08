import SwiftUI
import NebularNewsKit

/// 2-column grid of topic channel cards for the Discover tab.
struct DiscoverTopicGrid: View {
    let tags: [Tag]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let activeTags = tags.filter { ($0.articles?.count ?? 0) > 0 }

        if !activeTags.isEmpty {
            DashboardSectionHeader(
                title: "Topics",
                subtitle: "Browse by interest."
            )

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(activeTags, id: \.id) { tag in
                    NavigationLink(value: TopicDestination(id: tag.id, name: tag.name)) {
                        TopicChannelCard(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
