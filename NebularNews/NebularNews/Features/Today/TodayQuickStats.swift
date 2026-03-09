import SwiftUI
import NebularNewsKit

/// Horizontal scrolling row of stat pills for the Today briefing.
struct TodayQuickStats: View {
    let stats: TodayStats

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                QuickStatPill(label: "Unread", value: "\(stats.unreadCount)", icon: "envelope.badge", accent: .cyan)
                QuickStatPill(label: "New Today", value: "\(stats.newToday)", icon: "clock", accent: .orange)
                QuickStatPill(label: "High Fit", value: "\(stats.highFit)", icon: "star.fill", accent: Color.forScore(5))
            }
        }
    }
}

private struct QuickStatPill: View {
    let label: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassRoundedBackground(cornerRadius: 16))
    }
}
