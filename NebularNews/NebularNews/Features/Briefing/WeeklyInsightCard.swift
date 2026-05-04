import SwiftUI

/// Weekly Reading Insights card. Sits at the top of the Today tab when
/// a fresh insight is available and the user hasn't dismissed it for
/// this week. Visual identity matches BriefBulletCard so the surface
/// feels unified — same GlassRoundedBackground, same accent gradient,
/// same chip styling for tags.
struct WeeklyInsightCard: View {
    let insight: CompanionWeeklyInsight
    let onDismiss: () -> Void

    /// Top three topics, comma/dot separated for the stat strip. We
    /// truncate at three because anything beyond that crowds the card
    /// without adding signal — the full list is just behind a future
    /// "see more insights" surface if we ever want it.
    private var topTopics: [CompanionWeeklyInsight.Stats.Topic] {
        Array((insight.stats?.topTopics ?? []).prefix(3))
    }

    private var topFeedTitles: [String] {
        Array((insight.stats?.topFeeds ?? []).prefix(3)).map(\.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(insight.text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            if let stats = insight.stats {
                statRow(stats: stats)
            }

            if !topFeedTitles.isEmpty {
                Text("Most read: \(topFeedTitles.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassRoundedBackground(cornerRadius: 14))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("This week in your news")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide insight for this week")
        }
    }

    @ViewBuilder
    private func statRow(stats: CompanionWeeklyInsight.Stats) -> some View {
        HStack(spacing: 6) {
            Text("\(stats.articlesRead) article\(stats.articlesRead == 1 ? "" : "s") read")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())

            ForEach(topTopics, id: \.name) { topic in
                Text("#\(topic.name)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.platformTertiaryFill)
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}
