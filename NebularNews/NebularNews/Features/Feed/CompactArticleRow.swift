import SwiftUI
import NebularNewsKit

/// Compact row for score-3 and below articles in the magazine grid.
struct CompactArticleRow: View {
    let article: Article

    var body: some View {
        GlassCard(cornerRadius: 16, style: .compact, tintColor: Color.forScore(article.displayedScore)) {
            HStack(spacing: 12) {
                ScoreAccentBar(score: article.displayedScore, isRead: article.isRead || article.isDismissed)

                ArticleImageView(article: article, size: .thumbnail)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text((article.title ?? "Untitled").strippedHTML)
                        .font(NebularTypography.compactTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                        .allowsTightening(true)
                        .truncationMode(.tail)

                    if let summary = article.preferredCardSummaryText, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if let feedTitle = article.feed?.title {
                            Text(feedTitle.strippedHTML)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        ScoreBadge(score: article.displayedScore)

                        if let date = article.publishedAt {
                            Text(date.relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .opacity((article.isRead || article.isDismissed) ? 0.7 : 1)
    }
}
