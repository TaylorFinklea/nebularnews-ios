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

    @State private var searchText = ""
    @State private var filterMode: FeedFilterMode = .unread
    @State private var reactionSheetArticleID: String?
    @State private var viewModel = FeedBrowseViewModel()

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                List {
                    Section {
                        FeedFilterBar(filterMode: $filterMode, count: viewModel.visibleCount)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if viewModel.pendingPreparationCount > 0 {
                        Section {
                            FeedPreparingSection(count: viewModel.pendingPreparationCount)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if viewModel.isInitialLoadInProgress && viewModel.articles.isEmpty {
                        Section {
                            FeedSkeletonCard(height: 320, cornerRadius: 24)
                                .feedRowStyle(top: 0, bottom: 8)
                            FeedSkeletonCard(height: 190, cornerRadius: 16)
                                .feedRowStyle(top: 8, bottom: 8)
                            FeedSkeletonCard(height: 190, cornerRadius: 16)
                                .feedRowStyle(top: 8, bottom: 8)
                        }
                    } else if viewModel.articles.isEmpty {
                        Section {
                            ContentUnavailableView.search(text: searchText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .feedRowStyle(top: 0, bottom: 8)
                        }
                    } else {
                        if !featuredArticles.isEmpty {
                            Section {
                                ForEach(featuredArticles, id: \.id) { article in
                                    feedArticleRow(article)
                                }
                            }
                        }

                        if !standardArticles.isEmpty {
                            Section {
                                ForEach(standardArticles, id: \.id) { article in
                                    feedArticleRow(article)
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            Section {
                                FeedSkeletonCard(height: 190, cornerRadius: 16)
                                    .feedRowStyle(top: 8, bottom: 8)
                                FeedSkeletonCard(height: 190, cornerRadius: 16)
                                    .feedRowStyle(top: 8, bottom: 8)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
            .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
                viewModel.scheduleDebouncedReload(
                    container: modelContext.container,
                    filterMode: filterMode,
                    searchText: searchText
                )
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

    private var featuredArticles: [Article] {
        viewModel.articles.filter { ($0.displayedScore ?? 0) >= 4 }
    }

    private var standardArticles: [Article] {
        viewModel.articles.filter { ($0.displayedScore ?? 0) < 4 }
    }

    @ViewBuilder
    private func feedArticleRow(_ article: Article) -> some View {
        NavigationLink(value: article.id) {
            FeedArticleCard(article: article)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                handleReadToggle(for: article)
            } label: {
                Label(article.isRead ? "Unread" : "Read", systemImage: article.isRead ? "envelope.badge" : "checkmark.circle")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                presentReactionSheet(for: article)
            } label: {
                Label("React", systemImage: reactionSystemImage(for: article))
            }
            .tint(reactionTint(for: article))
        }
        .onAppear {
            handleArticleVisible(article)
        }
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
}

private struct FeedPreparingSection: View {
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

            Text("New stories stay offscreen until content, imagery, scoring, and summaries have had a first pass.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        count > 9 ? "Preparing fresh articles" : "Preparing \(count) article\(count == 1 ? "" : "s")"
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

private struct FeedArticleCard: View {
    let article: Article

    var body: some View {
        Group {
            if (article.displayedScore ?? 0) >= 4 {
                HeroArticleCard(article: article)
            } else {
                CompactArticleRow(article: article)
            }
        }
    }
}

private extension View {
    func feedRowStyle(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
    private var nextCursor: ArticleListCursor?
    private var reloadTask: Task<Void, Never>?

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

        async let visibleArticles = articleRepo.listFeedPage(
            filter: filter,
            cursor: nil,
            limit: initialBatchSize
        )
        async let visibleCount = articleRepo.countFeed(filter: filter)
        async let pendingCount = articleRepo.pendingVisibleArticleCount()

        let loadedArticles = await visibleArticles
        let loadedCount = await visibleCount
        let loadedPendingCount = await pendingCount

        guard token == requestToken else { return }

        articles = loadedArticles
        nextCursor = loadedArticles.last.map { ArticleListCursor(sortDate: $0.querySortDate, articleID: $0.id) }
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
        let nextBatch = await articleRepo.listFeedPage(
            filter: filter,
            cursor: nextCursor,
            limit: loadMoreBatchSize
        )

        let existingIDs = Set(articles.map(\.id))
        let appended = nextBatch.filter { !existingIDs.contains($0.id) }
        articles.append(contentsOf: appended)
        nextCursor = articles.last.map { ArticleListCursor(sortDate: $0.querySortDate, articleID: $0.id) }
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

    func scheduleDebouncedReload(
        container: ModelContainer,
        filterMode: FeedFilterMode,
        searchText: String
    ) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.reload(
                container: container,
                filterMode: filterMode,
                searchText: searchText
            )
        }
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
