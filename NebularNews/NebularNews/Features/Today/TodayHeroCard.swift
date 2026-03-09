import SwiftUI
import NebularNewsKit

/// Large hero card for the single top-scored article on the Today tab.
struct TodayHeroCard: View {
    let article: Article

    var body: some View {
        NavigationLink(value: article.id) {
            GlassImageCard(cornerRadius: 24, style: .hero, tintColor: Color.forScore(article.displayedScore)) {
                VStack(alignment: .leading, spacing: 0) {
                    ArticleImageView(article: article, size: .hero, dimmingOpacity: 0.18)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black.opacity(0.34), location: 0.3),
                                    .init(color: .black.opacity(0.68), location: 0.62),
                                    .init(color: .black.opacity(0.86), location: 1.0)
                                ],
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
                                        .minimumScaleFactor(0.74)
                                        .allowsTightening(true)
                                        .truncationMode(.tail)
                                        .tracking(-0.5)

                                    HStack(spacing: 8) {
                                        ScoreBadge(score: article.displayedScore)
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
                }
            }
        }
        .buttonStyle(.plain)
    }
}
