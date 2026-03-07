import SwiftUI
import SwiftData
import NebularNewsKit

/// Dashboard for standalone mode — shows reading momentum, top-scored articles, and quick actions.
///
/// Uses `@Query` for live SwiftData observation. Stats automatically update when
/// articles are polled, read, tagged, or rescored — no manual refresh needed.
struct StandaloneDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var allArticles: [Article]

    @Query private var feeds: [Feed]

    // MARK: - Computed Stats

    private var unreadCount: Int {
        allArticles.count(where: { !$0.isRead })
    }

    private var unread24h: Int {
        let cutoff = Date().addingTimeInterval(-86400)
        return allArticles.count(where: {
            !$0.isRead && ($0.publishedAt ?? .distantPast) > cutoff
        })
    }

    private var unread7d: Int {
        let cutoff = Date().addingTimeInterval(-604800)
        return allArticles.count(where: {
            !$0.isRead && ($0.publishedAt ?? .distantPast) > cutoff
        })
    }

    private var highFitUnread: Int {
        let cutoff = Date().addingTimeInterval(-604800)
        return allArticles.count(where: {
            !$0.isRead &&
            $0.hasReadyScore &&
            ($0.score ?? 0) >= 4 &&
            ($0.publishedAt ?? .distantPast) > cutoff
        })
    }

    private var scoredCount: Int {
        allArticles.count(where: \.hasReadyScore)
    }

    private var learningCount: Int {
        allArticles.count(where: \.isLearningScore)
    }

    /// Top unread articles sorted by score (descending), limited to 10.
    private var topUnread: [Article] {
        allArticles
            .filter { !$0.isRead && $0.hasReadyScore && $0.score != nil }
            .sorted {
                if ($0.score ?? 0) == ($1.score ?? 0) {
                    return ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
                }
                return ($0.score ?? 0) > ($1.score ?? 0)
            }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Momentum section
                    momentumSection

                    // Top scored articles
                    if !topUnread.isEmpty {
                        topArticlesSection
                    }

                    // Stats summary
                    statsSection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
        }
    }

    // MARK: - Momentum

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reading Momentum", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Unread",
                    value: "\(unreadCount)",
                    icon: "envelope.badge",
                    color: unreadCount > 0 ? Color.accentColor : .secondary
                )
                MetricCard(
                    title: "New Today",
                    value: "\(unread24h)",
                    icon: "clock",
                    color: unread24h > 0 ? .orange : .secondary
                )
                MetricCard(
                    title: "This Week",
                    value: "\(unread7d)",
                    icon: "calendar",
                    color: .secondary
                )
                MetricCard(
                    title: "High Fit",
                    value: "\(highFitUnread)",
                    icon: "star.fill",
                    color: highFitUnread > 0 ? Color.forScore(5) : .secondary
                )
            }
        }
    }

    // MARK: - Top Articles

    private var topArticlesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Unread", systemImage: "arrow.up.right")
                .font(.headline)

            ForEach(topUnread, id: \.id) { article in
                NavigationLink(value: article.id) {
                    HStack(spacing: 10) {
                        ScoreBadge(score: article.score)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title ?? "Untitled")
                                .font(.subheadline)
                                .lineLimit(2)
                            if let feedTitle = article.feed?.title {
                                Text(feedTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let date = article.publishedAt {
                            Text(date.relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Overview", systemImage: "chart.pie")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatPill(label: "Articles", value: "\(allArticles.count)")
                StatPill(label: "Feeds", value: "\(feeds.count)")
                StatPill(label: "Scored", value: "\(scoredCount)")
                StatPill(label: "Learning", value: "\(learningCount)")
            }
        }
    }
}

// MARK: - Supporting Views

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .modifier(GlassRoundedBackground(cornerRadius: 12))
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .modifier(GlassRoundedBackground(cornerRadius: 8))
    }
}
