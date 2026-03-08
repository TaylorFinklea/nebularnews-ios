import SwiftUI
import NebularNewsKit

struct StandaloneArticleRow: View {
    let article: Article

    var body: some View {
        GlassCard(cornerRadius: 22, style: (article.isRead || article.isDismissed) ? .standard : .raised, tintColor: accentColor) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                            Text(feedTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if article.isDismissed {
                            DismissedBadge()
                        }

                        if article.hasReadyScore, let score = article.displayedScore {
                            ScoreBadge(score: score)
                        } else if article.isLearningScore {
                            LearningBadge()
                        }

                        if let date = article.publishedAt {
                            Text(date.relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text(article.title ?? "Untitled")
                        .font(.headline)
                        .fontWeight((article.isRead || article.isDismissed) ? .regular : .semibold)
                        .foregroundStyle((article.isRead || article.isDismissed) ? .secondary : .primary)
                        .lineLimit(2)

                    if let summary = article.summaryText, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let excerpt = article.excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let author = article.author, !author.isEmpty {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .opacity((article.isRead || article.isDismissed) ? 0.78 : 1)
    }

    private var accentColor: Color {
        if article.isDismissed {
            return .secondary
        }
        if article.hasReadyScore, let score = article.displayedScore {
            return Color.forScore(score)
        }
        if article.isLearningScore {
            return .purple
        }
        return article.isRead ? .secondary : .cyan
    }
}

struct LearningBadge: View {
    var body: some View {
        Text("Learning")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.purple.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.purple.opacity(0.18)))
    }
}

struct DismissedBadge: View {
    var body: some View {
        Text("Dismissed")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18)))
    }
}
