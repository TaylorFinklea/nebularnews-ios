import SwiftUI
import NebularNewsKit

/// Visual card for a topic/tag in the Discover tab's topic grid.
struct TopicChannelCard: View {
    let tag: Tag

    var body: some View {
        let color = tagColor

        GlassCard(cornerRadius: 20, style: .raised, tintColor: color) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: iconForTag(tag.name))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(tag.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(tag.articles?.count ?? 0) articles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagColor: Color {
        guard let hex = tag.colorHex else {
            return .purple
        }
        return Color(hex: hex)
    }
}
