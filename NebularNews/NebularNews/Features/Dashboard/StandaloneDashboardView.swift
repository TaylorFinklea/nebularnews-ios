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
        allArticles.count(where: \.isUnreadQueueCandidate)
    }

    private var unread24h: Int {
        let cutoff = Date().addingTimeInterval(-86400)
        return allArticles.count(where: {
            $0.isUnreadQueueCandidate && ($0.publishedAt ?? .distantPast) > cutoff
        })
    }

    private var unread7d: Int {
        let cutoff = Date().addingTimeInterval(-604800)
        return allArticles.count(where: {
            $0.isUnreadQueueCandidate && ($0.publishedAt ?? .distantPast) > cutoff
        })
    }

    private var highFitUnread: Int {
        let cutoff = Date().addingTimeInterval(-604800)
        return allArticles.count(where: {
            $0.isUnreadQueueCandidate &&
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
            .filter { $0.isUnreadQueueCandidate && $0.hasReadyScore && $0.score != nil }
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
            NebularScreen {
                ScrollView {
                    VStack(spacing: 22) {
                        heroSection
                        momentumSection

                        if !topUnread.isEmpty {
                            topArticlesSection
                        }

                        statsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
        }
    }

    private var heroSection: some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: Color.forScore(5)) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reading momentum")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    Text(heroHeadline)
                        .font(.largeTitle.bold())
                        .tracking(-0.8)

                    Text(heroSubheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    HeroPill(label: "Unread", value: "\(unreadCount)", accent: .cyan)
                    HeroPill(label: "High Fit", value: "\(highFitUnread)", accent: Color.forScore(5))
                    HeroPill(label: "Scored", value: "\(scoredCount)", accent: .purple)
                }
            }
            .background(alignment: .topTrailing) {
                NebularHeaderHalo(color: Color.forScore(highFitUnread > 0 ? 5 : 4))
                    .offset(x: 54, y: -54)
            }
        }
    }

    private var heroHeadline: String {
        if highFitUnread > 0 {
            return "\(highFitUnread) strong matches are waiting"
        }
        if unread24h > 0 {
            return "\(unread24h) fresh stories landed today"
        }
        if unreadCount > 0 {
            return "Your queue is primed for a catch-up"
        }
        return "You’re fully caught up right now"
    }

    private var heroSubheadline: String {
        if unreadCount == 0 {
            return "Pull feeds again later or add a few more sources to keep the queue fresh."
        }
        return "Nebular surfaces the best reading opportunities first, while the rest of the queue stays close at hand."
    }

    // MARK: - Momentum

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(
                title: "Signals",
                subtitle: "A quick read on volume, recency, and fit."
            )

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
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(
                title: "Top unread",
                subtitle: "The strongest candidates in your current queue."
            )

            ForEach(topUnread, id: \.id) { article in
                NavigationLink(value: article.id) {
                    GlassCard(cornerRadius: 22, style: .standard, tintColor: Color.forScore(article.score)) {
                        HStack(spacing: 12) {
                            ScoreBadge(score: article.score)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title ?? "Untitled")
                                    .font(.headline)
                                    .lineLimit(2)
                                if let feedTitle = article.feed?.title {
                                    Text(feedTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            if let date = article.publishedAt {
                                Text(date.relativeDisplay)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(
                title: "Overview",
                subtitle: "The shape of your local news workspace."
            )

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
        GlassCard(cornerRadius: 22, style: .raised, tintColor: color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 36, height: 36)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                }

                Text(value)
                    .font(.title.bold())
                    .monospacedDigit()

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        GlassCard(cornerRadius: 18, style: .standard) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.headline.bold())
                    .monospacedDigit()
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HeroPill: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .background(accent.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.18)))
    }
}
