import SwiftUI
import NebularNewsKit

struct CompanionFilteredArticleListView: View {
    @Environment(AppState.self) private var appState

    let title: String
    let read: CompanionReadFilter
    let sort: CompanionSortOrder
    let sinceDays: Int?
    let minScore: Int?

    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage = ""

    private var hasMore: Bool { articles.count < total }

    var body: some View {
        List {
            if !errorMessage.isEmpty && articles.isEmpty {
                Section {
                    ErrorBanner(message: errorMessage) {
                        Task { await load() }
                    }
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                if articles.isEmpty && !isLoading && errorMessage.isEmpty {
                    ContentUnavailableView(
                        "No articles",
                        systemImage: "doc.text",
                        description: Text("No articles found for this filter.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(articles) { article in
                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                        ArticleCard(article: article)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await toggleRead(article) }
                        } label: {
                            Label(article.isRead == 1 ? "Unread" : "Read", systemImage: article.isRead == 1 ? "eye" : "eye.slash")
                        }
                        .tint(article.isRead == 1 ? .blue : .gray)
                    }
                }

                if hasMore {
                    HStack {
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { Task { await loadMore() } }
                        }
                        Spacer()
                    }
                }
            }

            if !errorMessage.isEmpty && !articles.isEmpty {
                Section {
                    ErrorBanner(message: errorMessage) {
                        Task { await loadMore() }
                    }
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .overlay {
            if isLoading && articles.isEmpty {
                ProgressView("Loading…")
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.supabase.fetchArticles(
                offset: 0,
                limit: PaginationConfig.companionPageSize,
                read: read,
                minScore: minScore,
                sort: sort,
                sinceDays: sinceDays
            )
            articles = payload.articles
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRead(_ article: CompanionArticleListItem) async {
        let newReadState = article.isRead != 1
        await appState.syncManager?.setRead(articleId: article.id, isRead: newReadState)
        await load()
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.supabase.fetchArticles(
                offset: articles.count,
                limit: PaginationConfig.companionPageSize,
                read: read,
                minScore: minScore,
                sort: sort,
                sinceDays: sinceDays
            )
            articles.append(contentsOf: payload.articles)
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
