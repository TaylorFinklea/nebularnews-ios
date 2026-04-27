import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct ReadingQueueEntry: TimelineEntry {
    let date: Date
    let articles: [WidgetArticle]
    let lastUpdated: Date?
}

// MARK: - Timeline Provider

struct ReadingQueueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingQueueEntry {
        ReadingQueueEntry(
            date: .now,
            articles: [
                WidgetArticle(id: "1", title: "UK sends troops to Middle East", score: 4, feedName: "BBC News", excerpt: nil),
                WidgetArticle(id: "2", title: "OpenAI announces new model capabilities", score: 3, feedName: "The Verge", excerpt: nil),
                WidgetArticle(id: "3", title: "New Swift concurrency features in Xcode 16", score: 3, feedName: "Swift Blog", excerpt: nil),
                WidgetArticle(id: "4", title: "Climate report warns of accelerating change", score: 3, feedName: "Reuters", excerpt: nil),
                WidgetArticle(id: "5", title: "Local council approves new transit plan", score: 2, feedName: "Local News", excerpt: nil),
            ],
            lastUpdated: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingQueueEntry) -> Void) {
        let entry = ReadingQueueEntry(
            date: .now,
            articles: WidgetDataProvider.loadTopArticles(limit: 5),
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingQueueEntry>) -> Void) {
        let entry = ReadingQueueEntry(
            date: .now,
            articles: WidgetDataProvider.loadTopArticles(limit: 5),
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct ReadingQueueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ReadingQueueEntry

    private var isStale: Bool {
        guard let updated = entry.lastUpdated else { return true }
        return Date().timeIntervalSince(updated) > 3600
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryRectangularBody
            default:
                if entry.articles.isEmpty {
                    emptyState
                } else {
                    articleList
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var accessoryRectangularBody: some View {
        Group {
            if let top = entry.articles.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next \u{00B7} \(entry.articles.count)")
                        .font(.caption2)
                        .widgetAccentable()
                    Text(top.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .privacySensitive()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "nebularnews://article/\(top.id)"))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading Queue")
                        .font(.caption2)
                        .widgetAccentable()
                    Text("Queue is empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "nebularnews://today"))
            }
        }
    }

    private var articleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Reading Queue")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if isStale {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Data may be stale")
                } else if let updated = entry.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 6)

            // Article rows
            ForEach(Array(entry.articles.enumerated()), id: \.element.id) { index, article in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 2)
                }
                if let url = URL(string: "nebularnews://article/\(article.id)") {
                    Link(destination: url) {
                        articleRow(article)
                    }
                } else {
                    articleRow(article)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func articleRow(_ article: WidgetArticle) -> some View {
        HStack(spacing: 8) {
            // Score indicator
            if let score = article.score {
                Text("\(score)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(scoreColor(score))
                    .frame(width: 16)
            } else {
                Color.clear
                    .frame(width: 16)
            }

            // Article info
            VStack(alignment: .leading, spacing: 1) {
                Text(article.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let feedName = article.feedName {
                    Text(feedName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("No articles yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open the app to load your reading queue")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "nebularnews://today"))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 1: Color(red: 0.99, green: 0.65, blue: 0.65)
        case 2: Color(red: 0.99, green: 0.73, blue: 0.45)
        case 3: Color(red: 0.77, green: 0.71, blue: 0.99)
        case 4: Color(red: 0.40, green: 0.91, blue: 0.98)
        case 5: Color(red: 0.53, green: 0.94, blue: 0.67)
        default: .secondary
        }
    }
}

// MARK: - Widget Configuration

struct ReadingQueueWidget: Widget {
    let kind = "ReadingQueueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadingQueueProvider()) { entry in
            ReadingQueueWidgetView(entry: entry)
        }
        .configurationDisplayName("Reading Queue")
        .description("Your top unread articles ranked by score.")
        #if os(iOS)
        .supportedFamilies([.systemLarge, .accessoryRectangular])
        #else
        .supportedFamilies([.systemLarge])
        #endif
    }
}

#Preview(as: .systemLarge) {
    ReadingQueueWidget()
} timeline: {
    ReadingQueueEntry(
        date: .now,
        articles: [
            WidgetArticle(id: "1", title: "UK sends troops to Middle East amid rising tensions", score: 4, feedName: "BBC News", excerpt: nil),
            WidgetArticle(id: "2", title: "OpenAI announces new model capabilities for developers", score: 3, feedName: "The Verge", excerpt: nil),
            WidgetArticle(id: "3", title: "New Swift concurrency features in Xcode 16", score: 3, feedName: "Swift Blog", excerpt: nil),
            WidgetArticle(id: "4", title: "Climate report warns of accelerating change worldwide", score: 3, feedName: "Reuters", excerpt: nil),
            WidgetArticle(id: "5", title: "Local council approves new transit infrastructure plan", score: 2, feedName: "Local News", excerpt: nil),
        ],
        lastUpdated: .now
    )
    ReadingQueueEntry(
        date: .now,
        articles: [],
        lastUpdated: nil
    )
}
