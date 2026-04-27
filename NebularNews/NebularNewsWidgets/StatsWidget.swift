import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct StatsEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats
    let lastUpdated: Date?
}

// MARK: - Timeline Provider

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(
            date: .now,
            stats: WidgetStats(unreadTotal: 42, newToday: 12, highFitUnread: 3),
            lastUpdated: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        let entry = StatsEntry(
            date: .now,
            stats: WidgetDataProvider.loadStats(),
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let entry = StatsEntry(
            date: .now,
            stats: WidgetDataProvider.loadStats(),
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct StatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    private var isEmpty: Bool {
        entry.stats.unreadTotal == 0 && entry.stats.newToday == 0 && entry.stats.highFitUnread == 0
    }

    private var isStale: Bool {
        guard let updated = entry.lastUpdated else { return true }
        return Date().timeIntervalSince(updated) > 3600
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                accessoryCircularBody
            case .accessoryInline:
                accessoryInlineBody
            default:
                homeScreenBody
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "nebularnews://today"))
    }

    private var accessoryCircularBody: some View {
        VStack(spacing: 1) {
            Text("\(entry.stats.unreadTotal)")
                .font(.title3.bold())
                .monospacedDigit()
                .widgetAccentable()
            Text("unread")
                .font(.caption2)
        }
    }

    private var accessoryInlineBody: some View {
        Text("\(Image(systemName: "envelope.badge")) \(entry.stats.unreadTotal) unread")
    }

    private var homeScreenBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Nebular News")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if isStale {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Data may be stale")
                }
            }

            if isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    Text("All caught up!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer()

                statRow(
                    icon: "envelope.badge",
                    label: "Unread",
                    value: entry.stats.unreadTotal,
                    color: entry.stats.unreadTotal > 0 ? Color.accentColor : .secondary
                )

                statRow(
                    icon: "clock",
                    label: "New",
                    value: entry.stats.newToday,
                    color: entry.stats.newToday > 0 ? .orange : .secondary
                )

                statRow(
                    icon: "star.fill",
                    label: "Top",
                    value: entry.stats.highFitUnread,
                    color: entry.stats.highFitUnread > 0 ? .green : .secondary
                )
            }
        }
    }

    private func statRow(icon: String, label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            Text("\(value)")
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Widget Configuration

struct StatsWidget: Widget {
    let kind = "StatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Reading Stats")
        .description("Your unread count, new articles, and top-fit stories at a glance.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}

#Preview(as: .systemSmall) {
    StatsWidget()
} timeline: {
    StatsEntry(
        date: .now,
        stats: WidgetStats(unreadTotal: 42, newToday: 12, highFitUnread: 3),
        lastUpdated: .now
    )
    StatsEntry(
        date: .now,
        stats: WidgetStats(unreadTotal: 0, newToday: 0, highFitUnread: 0),
        lastUpdated: nil
    )
}
