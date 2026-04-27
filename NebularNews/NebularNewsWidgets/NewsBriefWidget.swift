import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct NewsBriefEntry: TimelineEntry {
    let date: Date
    let brief: WidgetBrief?
}

// MARK: - Timeline Provider

struct NewsBriefProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewsBriefEntry {
        NewsBriefEntry(
            date: .now,
            brief: WidgetBrief(
                id: nil,
                title: "Morning Brief",
                editionLabel: "Morning",
                generatedAt: Date().timeIntervalSince1970,
                bullets: [
                    "Markets open higher on tech earnings beat",
                    "New AI model announced with multimodal support",
                    "Climate summit reaches tentative agreement",
                    "Major sports rivalry game tonight",
                    "Local transit expansion breaks ground"
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NewsBriefEntry) -> Void) {
        completion(NewsBriefEntry(date: .now, brief: WidgetDataProvider.loadBrief()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewsBriefEntry>) -> Void) {
        let entry = NewsBriefEntry(date: .now, brief: WidgetDataProvider.loadBrief())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget View

struct NewsBriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NewsBriefEntry

    private var containerBackground: some ShapeStyle {
        if family == .systemLarge {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color.accentColor.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(.fill.tertiary)
    }

    private var briefDeepLinkURL: URL? {
        if let id = entry.brief?.id, !id.isEmpty {
            return URL(string: "nebularnews://brief/\(id)")
        }
        return URL(string: "nebularnews://today")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryRectangularBody
            case .systemMedium:
                homeScreenBody(maxBullets: 3)
            default:
                homeScreenBody(maxBullets: 6)
            }
        }
        .containerBackground(containerBackground, for: .widget)
        .widgetURL(briefDeepLinkURL)
    }

    private var accessoryRectangularBody: some View {
        Group {
            if let brief = entry.brief, let first = brief.bullets.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brief.editionLabel + " Brief")
                        .font(.caption2)
                        .widgetAccentable()
                    Text(first)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .privacySensitive()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("News Brief")
                        .font(.caption2)
                        .widgetAccentable()
                    Text("No brief yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func homeScreenBody(maxBullets: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(entry.brief?.title ?? "News Brief")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let ts = entry.brief?.generatedAt {
                    Text(Date(timeIntervalSince1970: ts), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let bullets = entry.brief?.bullets, !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(bullets.prefix(maxBullets).enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "newspaper")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                    Text("Open the app to generate a brief")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget Configuration

struct NewsBriefWidget: Widget {
    let kind = "NewsBriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NewsBriefProvider()) { entry in
            NewsBriefWidgetView(entry: entry)
        }
        .configurationDisplayName("News Brief")
        .description("Latest morning/evening news brief bullets.")
        #if os(iOS)
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
        #else
        .supportedFamilies([.systemMedium, .systemLarge])
        #endif
    }
}

#Preview(as: .systemMedium) {
    NewsBriefWidget()
} timeline: {
    NewsBriefEntry(
        date: .now,
        brief: WidgetBrief(
            id: "preview-brief",
            title: "Morning Brief",
            editionLabel: "Morning",
            generatedAt: Date().timeIntervalSince1970,
            bullets: [
                "Markets open higher on tech earnings beat",
                "New AI model announced with multimodal support",
                "Climate summit reaches tentative agreement"
            ]
        )
    )
    NewsBriefEntry(date: .now, brief: nil)
}
