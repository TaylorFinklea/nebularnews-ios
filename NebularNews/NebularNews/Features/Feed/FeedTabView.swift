import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

/// Main Feed tab with magazine-style grid layout.
///
/// Articles are displayed in a score-driven magazine grid where
/// personalization scores determine visual prominence. Supports
/// filtering by read state and full-text search.
struct FeedTabView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var navigationPath: [String] = []
    @State private var searchText = ""
    @State private var filterMode: FeedFilterMode = .unread
    @State private var reactionSheetArticleID: String?
    @State private var isScrollInteractionActive = false
    @State private var viewModel = FeedBrowseViewModel()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            NebularScreen(emphasis: .reading) {
                ScrollView {
                    VStack(spacing: 16) {
                        FeedFilterBar(filterMode: $filterMode, count: viewModel.visibleCount)

                        if viewModel.pendingPreparationCount > 0 {
                            FeedPreparingSection(count: viewModel.pendingPreparationCount)
                        }

                        if viewModel.isInitialLoadInProgress && viewModel.articles.isEmpty {
                            FeedSkeletonSection()
                        } else if viewModel.articles.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            MagazineGrid(
                                articles: viewModel.articles,
                                isScrollInteractionActive: isScrollInteractionActive,
                                onOpenArticle: openArticle,
                                onToggleRead: handleReadToggle,
                                onReact: presentReactionSheet,
                                onArticleVisible: handleArticleVisible
                            )

                            if viewModel.isLoadingMore {
                                FeedLoadingMoreSection()
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .simultaneousGesture(scrollMonitorGesture)
            }
            .navigationTitle("Feed")
            .searchable(text: $searchText, prompt: "Search articles")
            .sheet(isPresented: isReactionSheetPresented) {
                if let article = selectedReactionArticle {
                    ReactionSheet(article: article, allowsDismiss: true)
                }
            }
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .task(id: reloadKey) {
                await viewModel.reload(
                    container: modelContext.container,
                    filterMode: filterMode,
                    searchText: searchText
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                Task {
                    await viewModel.reload(
                        container: modelContext.container,
                        filterMode: filterMode,
                        searchText: searchText
                    )
                }
            }
        }
    }

    private var reloadKey: String {
        "\(filterMode.rawValue)|\(searchText)"
    }

    private var selectedReactionArticle: Article? {
        guard let reactionSheetArticleID else { return nil }
        return liveArticle(for: reactionSheetArticleID)
    }

    private var isReactionSheetPresented: Binding<Bool> {
        Binding(
            get: { selectedReactionArticle != nil },
            set: { isPresented in
                if !isPresented {
                    reactionSheetArticleID = nil
                }
            }
        )
    }

    private func handleReadToggle(for article: Article) {
        Task {
            await viewModel.toggleReadState(
                for: article.id,
                container: modelContext.container,
                isRead: article.isRead
            )
        }
    }

    private func presentReactionSheet(for article: Article) {
        reactionSheetArticleID = article.id
    }

    private func openArticle(for article: Article) {
        navigationPath.append(article.id)
    }

    private func handleArticleVisible(_ article: Article) {
        Task {
            await viewModel.loadMoreIfNeeded(
                currentArticleID: article.id,
                container: modelContext.container,
                filterMode: filterMode,
                searchText: searchText
            )
        }
    }

    private func liveArticle(for articleID: String) -> Article? {
        viewModel.articles.first(where: { $0.id == articleID })
    }

    private var scrollMonitorGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if !isScrollInteractionActive {
                    isScrollInteractionActive = true
                }
            }
            .onEnded { _ in
                releaseScrollInteraction()
            }
    }

    private func releaseScrollInteraction() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            isScrollInteractionActive = false
        }
    }
}

private struct FeedPreparingSection: View {
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

                Text("New stories stay offscreen until content, imagery, scoring, and summaries have had a first pass.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FeedSkeletonSection: View {
    var body: some View {
        VStack(spacing: 16) {
            FeedSkeletonCard(height: 320, cornerRadius: 24)
            FeedSkeletonCard(height: 190, cornerRadius: 16)
            FeedSkeletonCard(height: 190, cornerRadius: 16)
        }
    }
}

private struct FeedLoadingMoreSection: View {
    var body: some View {
        VStack(spacing: 16) {
            FeedSkeletonCard(height: 190, cornerRadius: 16)
            FeedSkeletonCard(height: 190, cornerRadius: 16)
        }
    }
}

private struct FeedSkeletonCard: View {
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
private final class FeedBrowseViewModel {
    private let initialBatchSize = 30
    private let loadMoreBatchSize = 20

    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0
    private var totalVisibleCount = 0

    var articles: [Article] = []
    var visibleCount = 0
    var pendingPreparationCount = 0
    var isInitialLoadInProgress = false
    var isLoadingMore = false

    var hasMoreArticles: Bool {
        articles.count < totalVisibleCount
    }

    func reload(
        container: ModelContainer,
        filterMode: FeedFilterMode,
        searchText: String
    ) async {
        let articleRepo = repository(for: container)
        requestToken += 1
        let token = requestToken
        isInitialLoadInProgress = true

        let filter = makeFilter(filterMode: filterMode, searchText: searchText)
        let pendingFilter: ArticleFilter = {
            var filter = ArticleFilter()
            filter.presentationFilter = .pendingOnly
            return filter
        }()

        async let visibleArticles = articleRepo.listVisibleArticles(
            filter: filter,
            sort: .newest,
            limit: initialBatchSize,
            offset: 0
        )
        async let visibleCount = articleRepo.countVisibleArticles(filter: filter)
        async let pendingCount = articleRepo.count(filter: pendingFilter)

        let loadedArticles = await visibleArticles
        let loadedCount = await visibleCount
        let loadedPendingCount = await pendingCount

        guard token == requestToken else { return }

        articles = loadedArticles
        totalVisibleCount = loadedCount
        self.visibleCount = loadedCount
        pendingPreparationCount = loadedPendingCount
        isInitialLoadInProgress = false
        isLoadingMore = false
    }

    func loadMoreIfNeeded(
        currentArticleID: String,
        container: ModelContainer,
        filterMode: FeedFilterMode,
        searchText: String
    ) async {
        guard hasMoreArticles,
              !isLoadingMore,
              shouldLoadMore(after: currentArticleID)
        else {
            return
        }

        let articleRepo = repository(for: container)
        isLoadingMore = true
        let filter = makeFilter(filterMode: filterMode, searchText: searchText)
        let nextBatch = await articleRepo.listVisibleArticles(
            filter: filter,
            sort: .newest,
            limit: loadMoreBatchSize,
            offset: articles.count
        )

        let existingIDs = Set(articles.map(\.id))
        let appended = nextBatch.filter { !existingIDs.contains($0.id) }
        articles.append(contentsOf: appended)
        isLoadingMore = false
    }

    func toggleReadState(for articleID: String, container: ModelContainer, isRead: Bool) async {
        let articleRepo = repository(for: container)
        try? await articleRepo.markRead(id: articleID, isRead: !isRead)
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo {
            return articleRepo
        }

        let articleRepo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = articleRepo
        return articleRepo
    }

    private func shouldLoadMore(after articleID: String) -> Bool {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else {
            return false
        }

        return index >= max(0, articles.count - 5)
    }

    private func makeFilter(
        filterMode: FeedFilterMode,
        searchText: String
    ) -> ArticleFilter {
        var filter = ArticleFilter()
        filter.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch filterMode {
        case .unread:
            filter.readFilter = .unread
        case .all:
            break
        case .scored:
            filter.minScore = 1
        case .read:
            filter.readFilter = .read
        }

        return filter
    }
}
