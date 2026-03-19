import SwiftUI
import NebularNewsKit

/// Score-driven magazine layout using full-width cards at two prominence levels.
///
/// High-fit articles (score ≥ 4) appear as bold hero cards with large images,
/// while everything else uses compact rows — mirroring Apple News' hierarchy
/// through card height rather than column count.
struct MagazineGrid: View {
    let articles: [Article]
    let onArticleVisible: ((Article) -> Void)?

    init(
        articles: [Article],
        onArticleVisible: ((Article) -> Void)? = nil
    ) {
        self.articles = articles
        self.onArticleVisible = onArticleVisible
    }

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(layoutGroups) { group in
                switch group.tier {
                case .featured:
                    ForEach(group.articles, id: \.id) { article in
                        interactiveCard(for: article) {
                            HeroArticleCard(article: article)
                        }
                    }

                case .standard:
                    ForEach(group.articles, id: \.id) { article in
                        interactiveCard(for: article) {
                            CompactArticleRow(article: article)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layout Grouping

    private var layoutGroups: [LayoutGroup] {
        var groups: [LayoutGroup] = []

        let featured = articles.filter { ($0.displayedScore ?? 0) >= 4 }
        let standard = articles.filter { ($0.displayedScore ?? 0) < 4 }

        if !featured.isEmpty {
            groups.append(LayoutGroup(tier: .featured, articles: featured))
        }
        if !standard.isEmpty {
            groups.append(LayoutGroup(tier: .standard, articles: standard))
        }

        return groups
    }

    @ViewBuilder
    private func interactiveCard<Card: View>(
        for article: Article,
        @ViewBuilder content: () -> Card
    ) -> some View {
        NavigationLink(value: article.id) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            onArticleVisible?(article)
        }
    }
}

// MARK: - Supporting Types

private enum CardTier {
    case featured
    case standard
}

private struct LayoutGroup: Identifiable {
    let tier: CardTier
    let articles: [Article]

    /// Stable identity derived from tier + first article ID, so SwiftUI
    /// does not treat groups as new items on every body evaluation.
    var id: String {
        "\(tier)-\(articles.first?.id ?? "")"
    }
}
