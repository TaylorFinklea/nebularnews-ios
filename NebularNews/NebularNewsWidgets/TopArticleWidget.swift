import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct TopArticleEntry: TimelineEntry {
    let date: Date
    let article: WidgetArticle?
    let lastUpdated: Date?
}

// MARK: - Timeline Provider

struct TopArticleProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopArticleEntry {
        TopArticleEntry(
            date: .now,
            article: WidgetArticle(
                id: "placeholder",
                title: "Breaking: Major development in technology sector",
                score: 4,
                feedName: "BBC News",
                excerpt: "A significant announcement was made today regarding advances in artificial intelligence..."
            ),
            lastUpdated: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TopArticleEntry) -> Void) {
        let articles = WidgetDataProvider.loadTopArticles(limit: 1)
        let entry = TopArticleEntry(
            date: .now,
            article: articles.first,
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopArticleEntry>) -> Void) {
        let articles = WidgetDataProvider.loadTopArticles(limit: 1)
        let entry = TopArticleEntry(
            date: .now,
            article: articles.first,
            lastUpdated: WidgetDataProvider.lastUpdated()
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct TopArticleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TopArticleEntry

    private var isStale: Bool {
        guard let updated = entry.lastUpdated else { return true }
        return Date().timeIntervalSince(updated) > 3600
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryRectangularBody
            case .accessoryInline:
                accessoryInlineBody
            default:
                if let article = entry.article {
                    articleContent(article)
                } else {
                    emptyState
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var accessoryRectangularBody: some View {
        Group {
            if let article = entry.article {
                VStack(alignment: .leading, spacing: 2) {
                    if let feedName = article.feedName {
                        Text(feedName)
                            .font(.caption2)
                            .widgetAccentable()
                    }
                    Text(article.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .privacySensitive()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "nebularnews://article/\(article.id)"))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Article")
                        .font(.caption2)
                        .widgetAccentable()
                    Text("No articles yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "nebularnews://today"))
            }
        }
    }

    private var accessoryInlineBody: some View {
        Group {
            if let article = entry.article {
                Text("\(Image(systemName: "newspaper")) \(article.title)")
                    .privacySensitive()
                    .widgetURL(URL(string: "nebularnews://article/\(article.id)"))
            } else {
                Text("No top article")
                    .widgetURL(URL(string: "nebularnews://today"))
            }
        }
    }

    private func articleContent(_ article: WidgetArticle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Score + feed name row
            HStack(spacing: 6) {
                if let score = article.score {
                    scoreBadge(score)
                }
                if let feedName = article.feedName {
                    Text(feedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isStale {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Data may be stale")
                }
            }

            // Title
            Text(article.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Excerpt
            if let excerpt = article.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "nebularnews://article/\(article.id)"))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.title2)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("No articles yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open the app to load articles")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "nebularnews://today"))
    }

    private func scoreBadge(_ score: Int) -> some View {
        Text("\(score)/5")
            .font(.caption2.bold())
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(scoreColor(score).opacity(0.18), in: Capsule())
            .foregroundStyle(scoreColor(score))
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

struct TopArticleWidget: Widget {
    let kind = "TopArticleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TopArticleProvider()) { entry in
            TopArticleWidgetView(entry: entry)
        }
        .configurationDisplayName("Top Article")
        .description("Your highest-scored unread article.")
        #if os(iOS)
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemMedium])
        #endif
    }
}

#Preview(as: .systemMedium) {
    TopArticleWidget()
} timeline: {
    TopArticleEntry(
        date: .now,
        article: WidgetArticle(
            id: "1",
            title: "UK sends troops to Middle East amid rising tensions",
            score: 4,
            feedName: "BBC News",
            excerpt: "Defence secretary announces deployment of additional forces as regional security concerns grow."
        ),
        lastUpdated: .now
    )
    TopArticleEntry(
        date: .now,
        article: nil,
        lastUpdated: nil
    )
}
