import SwiftUI
import NebularNewsKit

/// Score-driven magazine layout using full-width cards at two prominence levels.
///
/// High-fit articles (score ≥ 4) appear as bold hero cards with large images,
/// while everything else uses compact rows — mirroring Apple News' hierarchy
/// through card height rather than column count.
struct MagazineGrid: View {
    let articles: [Article]

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(layoutGroups) { group in
                switch group.tier {
                case .featured:
                    ForEach(group.articles, id: \.id) { article in
                        NavigationLink(value: article.id) {
                            HeroArticleCard(article: article)
                        }
                        .buttonStyle(.plain)
                    }

                case .standard:
                    ForEach(group.articles, id: \.id) { article in
                        NavigationLink(value: article.id) {
                            CompactArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Layout Grouping

    private var layoutGroups: [LayoutGroup] {
        var groups: [LayoutGroup] = []

        let featured = articles.filter { ($0.score ?? 0) >= 4 }
        let standard = articles.filter { ($0.score ?? 0) < 4 }

        if !featured.isEmpty {
            groups.append(LayoutGroup(tier: .featured, articles: featured))
        }
        if !standard.isEmpty {
            groups.append(LayoutGroup(tier: .standard, articles: standard))
        }

        return groups
    }
}

// MARK: - Supporting Types

private enum CardTier {
    case featured
    case standard
}

private struct LayoutGroup: Identifiable {
    let id = UUID()
    let tier: CardTier
    let articles: [Article]
}
