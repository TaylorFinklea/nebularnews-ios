import SwiftUI
import NebularNewsKit

/// Simple native-style stat grid for the Today briefing.
struct TodayQuickStats: View {
    let stats: TodayStats

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                quickStat(label: "Unread", value: "\(stats.unreadCount)", icon: "envelope.badge", accent: .cyan)
                quickStat(label: "New Today", value: "\(stats.newToday)", icon: "clock", accent: .orange)
                quickStat(label: "High Fit", value: "\(stats.highFit)", icon: "star.fill", accent: Color.forScore(5))
            }
        }
    }

    @ViewBuilder
    private func quickStat(label: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)

            Text(value)
                .font(.headline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
