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
            .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.todaySnapshotChanged)) { _ in
                viewModel.scheduleDebouncedReload(container: modelContext.container)
            }
            .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
                viewModel.scheduleDebouncedReload(container: modelContext.container)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "sparkles")
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

    private var title: String {
        count > 9 ? "Preparing fresh articles" : "Preparing \(count) article\(count == 1 ? "" : "s")"
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
    private var reloadTask: Task<Void, Never>?

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

        async let snapshotTask = articleRepo.fetchTodaySnapshot()
        async let pendingCountTask = articleRepo.pendingVisibleArticleCount()
        let snapshot = await snapshotTask
        let pending = await pendingCountTask
        let articleIDs = [snapshot.heroArticleID].compactMap { $0 } + snapshot.upNextArticleIDs
        let loadedTopArticles = await articleRepo.listArticles(ids: articleIDs)

        guard token == requestToken else { return }

        stats = TodayStats(
            unreadCount: snapshot.unreadCount,
            newToday: snapshot.newTodayCount,
            newThisWeek: snapshot.newTodayCount,
            highFit: snapshot.highFitCount,
            scoredCount: snapshot.readyArticleCount,
            learningCount: 0,
            totalArticles: snapshot.readyArticleCount
        )
        self.topArticles = loadedTopArticles
        pendingPreparationCount = pending
        isLoading = false
    }

    func scheduleDebouncedReload(container: ModelContainer) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.reload(container: container)
        }
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
