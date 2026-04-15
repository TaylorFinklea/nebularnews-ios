import SwiftUI
import NebularNewsKit

struct CollectionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(AIAssistantCoordinator.self) private var aiAssistant

    let collection: CompanionCollection

    @State private var articles: [CompanionArticleListItem] = []
    @State private var collectionDetail: CompanionCollection?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showEditSheet = false

    private var displayCollection: CompanionCollection {
        collectionDetail ?? collection
    }

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage) { Task { await loadCollection() } }
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
            }

            if articles.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No articles",
                    systemImage: "doc.text",
                    description: Text("Add articles to this collection from the article detail view.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(articles) { article in
                NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                    ArticleCard(article: article)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await removeArticle(article) }
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }
        }
        .overlay {
            if isLoading && articles.isEmpty {
                ProgressView("Loading collection…")
            }
        }
        .navigationTitle(displayCollection.name)
        .toolbar {
            ToolbarItem(placement: .platformTrailing) {
                Menu {
                    Button { showEditSheet = true } label: {
                        Label("Edit Collection", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await loadCollection() }
        .onAppear {
            let refs = articles.prefix(10).map { a in
                AIArticleRef(id: a.id, title: a.title ?? "Untitled", score: a.score, source: a.sourceName)
            }
            aiAssistant.updateContext(AIPageContext(
                pageType: "collection",
                pageLabel: displayCollection.name,
                articles: Array(refs)
            ))
        }
        .task {
            if articles.isEmpty {
                await loadCollection()
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditCollectionSheet(collection: displayCollection) { updated in
                collectionDetail = updated
            }
        }
    }

    private func loadCollection() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await appState.supabase.fetchCollection(id: collection.id)
            articles = detail.articles
            collectionDetail = detail.collection
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeArticle(_ article: CompanionArticleListItem) async {
        do {
            try await appState.supabase.removeArticleFromCollection(collectionId: collection.id, articleId: article.id)
            articles.removeAll { $0.id == article.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
