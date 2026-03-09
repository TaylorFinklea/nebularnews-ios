import SwiftUI
import NebularNewsKit

/// Score-driven magazine layout using full-width cards at two prominence levels.
///
/// High-fit articles (score ≥ 4) appear as bold hero cards with large images,
/// while everything else uses compact rows — mirroring Apple News' hierarchy
/// through card height rather than column count.
struct MagazineGrid: View {
    let articles: [Article]
    let onOpenArticle: ((Article) -> Void)?
    let onToggleRead: ((Article) -> Void)?
    let onReact: ((Article) -> Void)?

    init(
        articles: [Article],
        onOpenArticle: ((Article) -> Void)? = nil,
        onToggleRead: ((Article) -> Void)? = nil,
        onReact: ((Article) -> Void)? = nil
    ) {
        self.articles = articles
        self.onOpenArticle = onOpenArticle
        self.onToggleRead = onToggleRead
        self.onReact = onReact
    }

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(layoutGroups) { group in
                switch group.tier {
                case .featured:
                    ForEach(group.articles, id: \.id) { article in
                        interactiveCard(for: article, cornerRadius: 24) {
                            HeroArticleCard(article: article)
                        }
                    }

                case .standard:
                    ForEach(group.articles, id: \.id) { article in
                        interactiveCard(for: article, cornerRadius: 16) {
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

    private func readAction(for article: Article) -> FeedSwipeActionDescriptor {
        FeedSwipeActionDescriptor(
            title: article.isRead ? "Unread" : "Read",
            systemImage: article.isRead ? "envelope.badge" : "checkmark.circle",
            tint: .blue,
            handler: {
                onToggleRead?(article)
            }
        )
    }

    private func reactionAction(for article: Article) -> FeedSwipeActionDescriptor {
        FeedSwipeActionDescriptor(
            title: "React",
            systemImage: reactionSystemImage(for: article),
            tint: reactionTint(for: article),
            handler: {
                onReact?(article)
            }
        )
    }

    private func reactionSystemImage(for article: Article) -> String {
        if article.isDismissed {
            return "eye.slash.fill"
        }

        switch article.reactionValue {
        case 1:
            return "hand.thumbsup.fill"
        case -1:
            return "hand.thumbsdown.fill"
        default:
            return "hand.thumbsup"
        }
    }

    private func reactionTint(for article: Article) -> Color {
        if article.isDismissed {
            return .orange
        }

        switch article.reactionValue {
        case 1:
            return .green
        case -1:
            return .red
        default:
            return .gray
        }
    }

    @ViewBuilder
    private func interactiveCard<Card: View>(
        for article: Article,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Card
    ) -> some View {
        if let onOpenArticle, onToggleRead != nil, onReact != nil {
            FeedSwipeContainer(
                cornerRadius: cornerRadius,
                leadingAction: readAction(for: article),
                trailingAction: reactionAction(for: article),
                onTap: {
                    onOpenArticle(article)
                }
            ) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            NavigationLink(value: article.id) {
                content()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
