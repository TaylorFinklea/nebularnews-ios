import SwiftUI
import NebularNewsKit

struct ArticleCard: View {
    let article: CompanionArticleListItem
    var style: ArticleCardStyle = .standard

    enum ArticleCardStyle {
        case standard   // Regular list card
        case hero       // Large hero card (Today tab)
        case compact    // Minimal (Up Next)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image (if available, not compact)
            if style != .compact, let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .frame(height: style == .hero ? DesignTokens.heroImageHeight : DesignTokens.cardImageHeight)
                    .clipped()
            }

            // Content area
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(article.title ?? "Untitled")
                    .font(style == .hero ? .title3.bold() : .headline)
                    .lineLimit(style == .hero ? 3 : 2)

                // Source + relative time
                HStack(spacing: 6) {
                    if let source = article.sourceName {
                        Text(source)
                    }
                    Text("\u{00B7}")
                    Text(relativeTime(article.publishedAt ?? article.fetchedAt))
                    Spacer()
                    if let score = article.score {
                        ScoreBadge(score: score)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Summary (not compact)
                if style != .compact {
                    let summary = article.summaryText ?? article.excerpt
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(style == .hero ? 4 : 2)
                    }
                }

                // Tags (not compact)
                if style != .compact, let tags = article.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3)) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.platformTertiaryFill, in: Capsule())
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(style == .compact ? 10 : 12)
        }
        .background(Color.platformSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            // Score accent bar on left edge
            HStack {
                ScoreAccentBar(score: article.score, isRead: article.isReadBool, width: 4)
                Spacer()
            }
        )
        .opacity(article.isReadBool ? 0.6 : 1.0)
    }

    private func relativeTime(_ timestamp: Int?) -> String {
        guard let timestamp else { return "" }
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
