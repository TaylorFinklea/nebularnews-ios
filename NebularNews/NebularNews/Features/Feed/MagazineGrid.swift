import SwiftUI
import NebularNewsKit

/// Score-driven magazine layout that maps article scores to card sizes.
///
/// Score 5 articles get full-width hero cards, score 4 gets a 2-column
/// grid of medium cards, and everything else gets compact rows. Within
/// each tier, articles maintain chronological ordering.
struct MagazineGrid: View {
    let articles: [Article]

    private let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(layoutGroups) { group in
                switch group.tier {
                case .hero:
                    ForEach(group.articles, id: \.id) { article in
                        NavigationLink(value: article.id) {
                            HeroArticleCard(article: article)
                        }
                        .buttonStyle(.plain)
                    }

                case .medium:
                    LazyVGrid(columns: twoColumns, spacing: 12) {
                        ForEach(group.articles, id: \.id) { article in
                            NavigationLink(value: article.id) {
                                MediumArticleCard(article: article)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                case .compact:
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

        let heroArticles = articles.filter { ($0.score ?? 0) >= 5 }
        let mediumArticles = articles.filter { ($0.score ?? 0) == 4 }
        let compactArticles = articles.filter { ($0.score ?? 0) < 4 }

        if !heroArticles.isEmpty {
            groups.append(LayoutGroup(tier: .hero, articles: heroArticles))
        }
        if !mediumArticles.isEmpty {
            groups.append(LayoutGroup(tier: .medium, articles: mediumArticles))
        }
        if !compactArticles.isEmpty {
            groups.append(LayoutGroup(tier: .compact, articles: compactArticles))
        }

        return groups
    }
}

// MARK: - Supporting Types

private enum CardTier {
    case hero
    case medium
    case compact
}

private struct LayoutGroup: Identifiable {
    let id = UUID()
    let tier: CardTier
    let articles: [Article]
}
