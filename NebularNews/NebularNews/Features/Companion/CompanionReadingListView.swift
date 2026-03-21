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
                        ReadingListRow(article: article)
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
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
            let payload = try await appState.mobileAPI.fetchSavedArticles()
            articles = payload.articles
            errorMessage = ""
            await CompanionCache.shared.store(payload.articles, category: .savedArticles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unsaveArticle(_ article: CompanionArticleListItem) async {
        do {
            _ = try await appState.mobileAPI.saveArticle(id: article.id, saved: false)
            articles.removeAll { $0.id == article.id }
            await CompanionCache.shared.store(articles, category: .savedArticles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReadingListRow: View {
    let article: CompanionArticleListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoreAccentBar(score: article.score, isRead: article.isRead == 1, width: 3)
                .frame(height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "Untitled article")
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let sourceName = article.sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                    }
                    if let score = article.score {
                        ScoreBadge(score: score)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "bookmark.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
