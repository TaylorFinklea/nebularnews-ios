import SwiftUI
import NebularNewsKit

/// Half-width card for score-4 articles, displayed in a 2-column grid.
struct MediumArticleCard: View {
    let article: Article

    var body: some View {
        GlassImageCard(cornerRadius: 20, style: .medium, tintColor: Color.forScore(article.score)) {
            VStack(alignment: .leading, spacing: 0) {
                ArticleImageView(article: article, size: .medium)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    if let feedTitle = article.feed?.title {
                        Text(feedTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .lineLimit(1)
                    }

                    Text(article.title ?? "Untitled")
                        .font(NebularTypography.mediumCardTitle)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ScoreBadge(score: article.score)

                        Spacer()

                        if let date = article.publishedAt {
                            Text(date.relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(12)
            }
        }
        .opacity(article.isRead ? 0.75 : 1)
    }
}
