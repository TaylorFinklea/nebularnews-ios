import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

/// Today tab — a smart briefing combining stats with top-scored articles.
///
/// This is the primary landing screen, replacing the old Dashboard tab.
/// It shows a time-of-day greeting, quick stats, the top article as a
/// hero card, and a prioritized list of the next best reads.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showSettings = false
    @State private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .hero) {
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.isLoading && viewModel.topArticles.isEmpty {
                            TodaySkeletonView()
                        } else {
                            TodayBriefingHeader(stats: viewModel.stats)
                            TodayQuickStats(stats: viewModel.stats)

                            if viewModel.pendingPreparationCount > 0 {
                                TodayPreparingSection(count: viewModel.pendingPreparationCount)
                            }

                            if let hero = viewModel.topArticles.first {
                                DashboardSectionHeader(
                                    title: "Top pick",
                                    subtitle: "Your strongest match right now."
                                )
                                TodayHeroCard(article: hero)
                            }

                            if viewModel.topArticles.count > 1 {
                                DashboardSectionHeader(
                                    title: "Up next",
                                    subtitle: "More high-fit articles to explore."
                                )

                                ForEach(viewModel.topArticles.dropFirst(), id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        CompactArticleRow(article: article)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(showsDismissButton: true)
                }
            }
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .task {
                await viewModel.reload(container: modelContext.container)
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                Task {
                    await viewModel.reload(container: modelContext.container)
                }
            }
        }
    }
}

private struct TodaySkeletonView: View {
    var body: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 170)
                .redacted(reason: .placeholder)

            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 110, height: 64)
                        .redacted(reason: .placeholder)
                }
            }

            TodaySkeletonCard(height: 260, cornerRadius: 24)
            TodaySkeletonCard(height: 150, cornerRadius: 16)
            TodaySkeletonCard(height: 150, cornerRadius: 16)
        }
    }
}

private struct TodayPreparingSection: View {
    let count: Int

    var body: some View {
        GlassCard(cornerRadius: 22, style: .raised, tintColor: .cyan) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Preparing \(count) article\(count == 1 ? "" : "s")", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Fresh stories finish content, imagery, scoring, and summaries before they appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TodaySkeletonCard: View {
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.18))
                        .frame(width: 160, height: 12)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.26))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.18))
                        .frame(width: 220, height: 18)
                }
                .padding(18)
            }
            .redacted(reason: .placeholder)
    }
}

@Observable
@MainActor
private final class TodayViewModel {
    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0

    var stats = TodayStats(
        unreadCount: 0,
        newToday: 0,
        newThisWeek: 0,
        highFit: 0,
        scoredCount: 0,
        learningCount: 0,
        totalArticles: 0
    )
    var topArticles: [Article] = []
    var pendingPreparationCount = 0
    var isLoading = false

    func reload(container: ModelContainer) async {
        let articleRepo = repository(for: container)
        requestToken += 1
        let token = requestToken
        isLoading = true

        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)
        let weekAgo = now.addingTimeInterval(-604_800)

        let unreadFilter: ArticleFilter = {
            var filter = ArticleFilter()
            filter.readFilter = .unread
            return filter
        }()

        let unreadTodayFilter: ArticleFilter = {
            var filter = unreadFilter
            filter.publishedAfter = dayAgo
            return filter
        }()

        let unreadWeekFilter: ArticleFilter = {
            var filter = unreadFilter
            filter.publishedAfter = weekAgo
            return filter
        }()

        let highFitFilter: ArticleFilter = {
            var filter = unreadWeekFilter
            filter.minScore = 4
            return filter
        }()

        let scoredFilter: ArticleFilter = {
            var filter = ArticleFilter()
            filter.minScore = 1
            return filter
        }()

        let pendingFilter: ArticleFilter = {
            var filter = ArticleFilter()
            filter.presentationFilter = .pendingOnly
            return filter
        }()

        let topFilter: ArticleFilter = {
            var filter = unreadFilter
            filter.minScore = 1
            return filter
        }()

        async let totalArticles = articleRepo.countVisibleArticles(filter: ArticleFilter())
        async let unreadCount = articleRepo.countVisibleArticles(filter: unreadFilter)
        async let unreadTodayCount = articleRepo.countVisibleArticles(filter: unreadTodayFilter)
        async let unreadWeekCount = articleRepo.countVisibleArticles(filter: unreadWeekFilter)
        async let highFitCount = articleRepo.countVisibleArticles(filter: highFitFilter)
        async let scoredCount = articleRepo.countVisibleArticles(filter: scoredFilter)
        async let pendingCount = articleRepo.count(filter: pendingFilter)
        async let topArticles = articleRepo.listVisibleArticles(
            filter: topFilter,
            sort: .scoreDesc,
            limit: 10,
            offset: 0
        )

        let total = await totalArticles
        let unread = await unreadCount
        let today = await unreadTodayCount
        let week = await unreadWeekCount
        let highFit = await highFitCount
        let scored = await scoredCount
        let pending = await pendingCount
        let loadedTopArticles = await topArticles

        guard token == requestToken else { return }

        stats = TodayStats(
            unreadCount: unread,
            newToday: today,
            newThisWeek: week,
            highFit: highFit,
            scoredCount: scored,
            learningCount: max(total - scored, 0),
            totalArticles: total
        )
        self.topArticles = loadedTopArticles.sorted {
            let lhsScore = $0.displayedScore ?? 0
            let rhsScore = $1.displayedScore ?? 0

            if lhsScore == rhsScore {
                return ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
            }

            return lhsScore > rhsScore
        }
        pendingPreparationCount = pending
        isLoading = false
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo {
            return articleRepo
        }

        let articleRepo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = articleRepo
        return articleRepo
    }
}
