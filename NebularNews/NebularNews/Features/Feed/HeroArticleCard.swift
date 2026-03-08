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

        GlassImageCard(cornerRadius: 24, style: .hero, tintColor: Color.forScore(article.displayedScore)) {
            VStack(alignment: .leading, spacing: 0) {
                ArticleImageView(article: article, size: .hero)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        // Aggressive scrim gradient — ensures white text is
                        // legible on any image, including those with embedded text.
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.25), location: 0.3),
                                .init(color: .black.opacity(0.6), location: 0.55),
                                .init(color: .black.opacity(0.82), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let feedTitle = article.feed?.title {
                                Text(feedTitle.strippedHTML)
                                    .font(NebularTypography.feedSource)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .textCase(.uppercase)
                                    .tracking(0.7)
                                    .lineLimit(1)
                            }

                            Text((article.title ?? "Untitled").strippedHTML)
                                .font(NebularTypography.heroTitle)
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)

                            HStack(spacing: 8) {
                                ScoreBadge(score: article.displayedScore)

                                Spacer()

                                if let date = article.publishedAt {
                                    Text(date.relativeDisplay)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
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
