import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

/// Dashboard for standalone mode — shows reading momentum, top-scored articles, and quick actions.
///
/// Uses a debounced view model backed by the TodaySnapshot and targeted count queries,
/// rather than an unbounded @Query that recomputes on every article mutation.
struct StandaloneDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var feeds: [Feed]

    @State private var viewModel = StandaloneDashboardViewModel()

    private var unreadCount: Int { viewModel.unreadCount }
    private var unread24h: Int { viewModel.unread24h }
    private var unread7d: Int { viewModel.unread7d }
    private var highFitUnread: Int { viewModel.highFitUnread }
    private var scoredCount: Int { viewModel.scoredCount }
    private var learningCount: Int { viewModel.learningCount }
    private var topUnread: [Article] { viewModel.topUnread }
    private var totalArticles: Int { viewModel.totalArticles }

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
        .task {
            await viewModel.reload(container: modelContext.container)
        }
        .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
            viewModel.scheduleDebouncedReload(container: modelContext.container)
        }
        .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.todaySnapshotChanged)) { _ in
            viewModel.scheduleDebouncedReload(container: modelContext.container)
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
                    GlassCard(cornerRadius: 22, style: .standard, tintColor: Color.forScore(article.displayedScore)) {
                        HStack(spacing: 12) {
                            ScoreBadge(score: article.displayedScore)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title ?? "Untitled")
                                    .font(.headline)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                    .allowsTightening(true)
                                    .truncationMode(.tail)
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
                StatPill(label: "Articles", value: "\(totalArticles)")
                StatPill(label: "Feeds", value: "\(feeds.count)")
                StatPill(label: "Scored", value: "\(scoredCount)")
                StatPill(label: "Learning", value: "\(learningCount)")
            }
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
private final class StandaloneDashboardViewModel {
    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0
    private var reloadTask: Task<Void, Never>?

    var unreadCount = 0
    var unread24h = 0
    var unread7d = 0
    var highFitUnread = 0
    var scoredCount = 0
    var learningCount = 0
    var totalArticles = 0
    var topUnread: [Article] = []

    func reload(container: ModelContainer) async {
        let repo = repository(for: container)
        requestToken += 1
        let token = requestToken

        async let snapshotTask = repo.fetchTodaySnapshot()
        async let totalTask = repo.count(filter: ArticleFilter())

        let snapshot = await snapshotTask
        let total = await totalTask

        // Load top articles from the pre-computed snapshot (hero + upNext)
        let articleIDs = [snapshot.heroArticleID].compactMap { $0 } + snapshot.upNextArticleIDs
        let loaded = await repo.listArticles(ids: articleIDs)

        // unread7d and learningCount require a lightweight full-article pass,
        // but it runs once here rather than on every SwiftData observation.
        var unread7dCount = 0
        var learningCountValue = 0
        if let all = try? await fetchAllActive(repo: repo) {
            let sevenDaysAgo = Date().addingTimeInterval(-604800)
            unread7dCount = all.count(where: {
                $0.isUnreadQueueCandidate && ($0.publishedAt ?? .distantPast) > sevenDaysAgo
            })
            learningCountValue = all.count(where: \.isLearningScore)
        }

        guard token == requestToken else { return }

        unreadCount = snapshot.unreadCount
        unread24h = snapshot.newTodayCount
        unread7d = unread7dCount
        highFitUnread = snapshot.highFitCount
        scoredCount = snapshot.readyArticleCount
        learningCount = learningCountValue
        totalArticles = total
        topUnread = loaded
    }

    func scheduleDebouncedReload(container: ModelContainer) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            await self.reload(container: container)
        }
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo { return articleRepo }
        let repo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = repo
        return repo
    }

    private func fetchAllActive(repo: LocalArticleRepository) async throws -> [Article] {
        var filter = ArticleFilter()
        filter.storageScope = .active
        return await repo.list(filter: filter, sort: .newest, limit: 5000, offset: 0)
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
