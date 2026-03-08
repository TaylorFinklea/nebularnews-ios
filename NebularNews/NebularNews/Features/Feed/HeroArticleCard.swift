import SwiftUI
import NebularNewsKit

/// Full-width hero card for score-5 articles in the magazine grid.
///
/// Features a large image with text overlaid on a gradient, giving
/// the top-scored articles maximum visual prominence.
struct HeroArticleCard: View {
    let article: Article

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        GlassImageCard(cornerRadius: 24, style: .hero, tintColor: Color.forScore(article.score)) {
            VStack(alignment: .leading, spacing: 0) {
                ArticleImageView(article: article, size: .hero)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, palette.cardImageOverlay],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let feedTitle = article.feed?.title {
                                    Text(feedTitle)
                                        .font(NebularTypography.feedSource)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .textCase(.uppercase)
                                        .tracking(0.7)
                                }

                                Text(article.title ?? "Untitled")
                                    .font(NebularTypography.heroTitle)
                                    .foregroundStyle(.white)
                                    .lineLimit(3)
                                    .tracking(-0.5)

                                HStack(spacing: 8) {
                                    ScoreBadge(score: article.score)

                                    Spacer()

                                    if let date = article.publishedAt {
                                        Text(date.relativeDisplay)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }

                if let summary = article.summaryText, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}
