import SwiftUI
import NebularNewsKit

/// Greeting card with contextual headline based on reading state.
struct TodayBriefingHeader: View {
    let stats: TodayStats

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: Color.forScore(5)) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    Text(headline)
                        .font(.largeTitle.bold())
                        .tracking(-0.8)

                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(alignment: .topTrailing) {
                NebularHeaderHalo(color: Color.forScore(stats.highFit > 0 ? 5 : 4))
                    .offset(x: 54, y: -54)
            }
        }
    }

    // MARK: - Private

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night reading"
        }
    }

    private var headline: String {
        if stats.highFit > 0 {
            return "\(stats.highFit) strong matches waiting"
        }
        if stats.newToday > 0 {
            return "\(stats.newToday) fresh stories today"
        }
        if stats.unreadCount > 0 {
            return "Your queue is ready"
        }
        return "All caught up"
    }

    private var subheadline: String {
        if stats.unreadCount == 0 {
            return "Check back later or add more sources to keep the queue fresh."
        }
        return "Nebular surfaces the best reading opportunities first."
    }
}
