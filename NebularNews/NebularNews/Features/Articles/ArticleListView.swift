import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

struct ArticleListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var viewModel = ArticleListViewModel()

    /// Optional feed filter — when set, only shows articles from this feed.
    /// Set via navigation from FeedListView.
    let feedId: String?
    let feedTitle: String?

    init(feedId: String? = nil, feedTitle: String? = nil) {
        self.feedId = feedId
        self.feedTitle = feedTitle
    }

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case read = "Read"
        case scored = "Scored"
        case learning = "Learning"
    }

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                Group {
                    if viewModel.totalCount == 0 && !viewModel.isLoading {
                        ContentUnavailableView(
                            "No Articles Yet",
                            systemImage: "doc.text",
                            description: Text("Go to More \u{2192} Feeds to add an RSS feed, then pull to refresh.")
                        )
                    } else if viewModel.articles.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            Section {
                                LabeledContent("Articles", value: "\(viewModel.articles.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LabeledContent("Filter") {
                                    Picker("Filter", selection: $filterMode) {
                                        ForEach(FilterMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue)
                                                .tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reading queue")
                                    Text(filterSummaryText)
                                        .textCase(nil)
                                }
                            }

                            Section {
                                ForEach(viewModel.articles, id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        StandaloneArticleRow(article: article)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            handleLeadingSwipe(for: article)
                                        } label: {
                                            swipeActionLabel(for: article)
                                        }
                                        .tint(swipeTint(for: article))
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(feedTitle ?? "Articles")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .searchable(text: $searchText, prompt: "Search articles")
            .task(id: reloadKey) {
                await viewModel.reload(
                    container: modelContext.container,
                    filterMode: filterMode,
                    searchText: searchText,
                    feedId: feedId
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
                viewModel.scheduleDebouncedReload(
                    container: modelContext.container,
                    filterMode: filterMode,
                    searchText: searchText,
                    feedId: feedId
                )
            }
        }
    }

    private var reloadKey: ArticleListReloadKey {
        ArticleListReloadKey(
            filterMode: filterMode,
            searchText: searchText,
            feedId: feedId
        )
    }

    private var filterSummaryText: String {
        switch filterMode {
        case .all:
            return "Everything available across your current feeds."
        case .unread:
            return "Only unread stories that still need attention."
        case .read:
            return "Stories you already worked through."
        case .scored:
            return "Items with a ready fit score."
        case .learning:
            return "Items still gathering preference signals."
        }
    }

    private func handleLeadingSwipe(for article: Article) {
        if article.isRead {
            article.markUnread()
            try? modelContext.save()
            syncStandaloneState(for: article.id)
            return
        }

        if article.isDismissed {
            article.clearDismissal()
            try? modelContext.save()
            syncStandaloneState(for: article.id)
            return
        }

        let previousDismissedAt = article.dismissedAt
        article.markDismissed()
        let newDismissedAt = article.dismissedAt
        try? modelContext.save()

        Task {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            try? await articleRepo.syncStandaloneUserState(id: article.id)
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.processDismissChange(
                articleID: article.id,
                previousDismissedAt: previousDismissedAt,
                newDismissedAt: newDismissedAt
            )
        }
    }

    private func syncStandaloneState(for articleID: String) {
        Task {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            try? await articleRepo.syncStandaloneUserState(id: articleID)
        }
    }

    private func swipeActionLabel(for article: Article) -> some View {
        Label(
            swipeActionTitle(for: article),
            systemImage: swipeActionSystemImage(for: article)
        )
    }

    private func swipeActionTitle(for article: Article) -> String {
        if article.isRead {
            return "Unread"
        }
        return article.isDismissed ? "Undismiss" : "Dismiss"
    }

    private func swipeActionSystemImage(for article: Article) -> String {
        if article.isRead {
            return "envelope.badge"
        }
        return article.isDismissed ? "arrow.uturn.backward.circle" : "eye.slash"
    }

    private func swipeTint(for article: Article) -> Color {
        if article.isRead {
            return .blue
        }
        return article.isDismissed ? .orange : .secondary
    }
}

// MARK: - Reload Key

private struct ArticleListReloadKey: Equatable {
    let filterMode: ArticleListView.FilterMode
    let searchText: String
    let feedId: String?
}

// MARK: - ViewModel

@Observable
@MainActor
private final class ArticleListViewModel {
    private let batchSize = 200

    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0
    private var reloadTask: Task<Void, Never>?

    var articles: [Article] = []
    var totalCount = 0
    var isLoading = false

    func reload(
        container: ModelContainer,
        filterMode: ArticleListView.FilterMode,
        searchText: String,
        feedId: String?
    ) async {
        let repo = repository(for: container)
        requestToken += 1
        let token = requestToken
        isLoading = true

        let filter = makeFilter(filterMode: filterMode, searchText: searchText, feedId: feedId)

        async let loadedArticles = repo.listFeedPage(
            filter: filter,
            sort: .newest,
            cursor: nil,
            limit: batchSize
        )
        async let loadedCount = repo.countFeed(filter: filter)

        let fetchedArticles = await loadedArticles
        let fetchedCount = await loadedCount

        guard token == requestToken else { return }

        articles = fetchedArticles
        totalCount = fetchedCount
        isLoading = false
    }

    func scheduleDebouncedReload(
        container: ModelContainer,
        filterMode: ArticleListView.FilterMode,
        searchText: String,
        feedId: String?
    ) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.reload(
                container: container,
                filterMode: filterMode,
                searchText: searchText,
                feedId: feedId
            )
        }
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo { return articleRepo }
        let repo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = repo
        return repo
    }

    private func makeFilter(
        filterMode: ArticleListView.FilterMode,
        searchText: String,
        feedId: String?
    ) -> ArticleFilter {
        var filter = ArticleFilter()
        filter.feedId = feedId
        filter.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch filterMode {
        case .all: break
        case .unread: filter.readFilter = .unread
        case .read: filter.readFilter = .read
        case .scored: filter.minScore = 1
        case .learning: filter.maxScore = 0
        }

        return filter
    }
}
