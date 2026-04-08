import SwiftUI
import NebularNewsKit

struct CompanionReadingListView: View {
    @Environment(AppState.self) private var appState

    @Binding var showSettings: Bool

    @State private var articles: [CompanionArticleListItem] = []
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty {
                    ErrorBanner(message: errorMessage) { Task { await loadSaved() } }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }

                if articles.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No saved articles",
                        systemImage: "bookmark",
                        description: Text("Save articles from the article detail view to read later.")
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
                            Task { await unsaveArticle(article) }
                        } label: {
                            Label("Unsave", systemImage: "bookmark.slash")
                        }
                        .tint(.orange)
                    }
                }
            }
            .overlay {
                if isLoading && articles.isEmpty {
                    ProgressView("Loading saved articles…")
                }
            }
            .navigationTitle("Reading List")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
                #endif
            }
            .refreshable { await loadSaved() }
            .task {
                if articles.isEmpty {
                    // Show cached immediately
                    if let cached = await CompanionCache.shared.load([CompanionArticleListItem].self, category: .savedArticles) {
                        articles = cached
                    }
                    await loadSaved()
                }
            }
        }
    }

    private func loadSaved() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.supabase.fetchArticles(saved: true)
            articles = payload.articles
            errorMessage = ""
            await CompanionCache.shared.store(payload.articles, category: .savedArticles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unsaveArticle(_ article: CompanionArticleListItem) async {
        _ = await appState.syncManager?.saveArticle(articleId: article.id, saved: false)
        articles.removeAll { $0.id == article.id }
        await CompanionCache.shared.store(articles, category: .savedArticles)
    }
}
