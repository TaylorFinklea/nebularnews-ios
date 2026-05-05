import SwiftUI
import NebularNewsKit

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(AIAssistantCoordinator.self) private var aiAssistant

    @Binding var showSettings: Bool

    @State private var savedArticles: [CompanionArticleListItem] = []
    @State private var collections: [CompanionCollection] = []
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showCreateSheet = false

    /// Mirror MainTabView's setting. When the dedicated Articles tab is
    /// hidden (default), surface a "Browse all articles" link in Library
    /// so the firehose stays one tap away.
    @AppStorage("showArticlesTab") private var showArticlesTab = false

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty {
                    ErrorBanner(message: errorMessage) { Task { await loadAll() } }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }

                conversationHistorySection

                readHistorySection

                if !showArticlesTab {
                    browseAllSection
                }

                savedSection

                collectionsSection
            }
            .overlay {
                if isLoading && savedArticles.isEmpty && collections.isEmpty {
                    ProgressView("Loading library…")
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .platformTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
            }
            .refreshable { await loadAll() }
            .onAppear {
                let refs = savedArticles.prefix(10).map { a in
                    AIArticleRef(id: a.id, title: a.title ?? "Untitled", score: a.score, source: a.sourceName)
                }
                aiAssistant.updateContext(AIPageContext(pageType: "library", pageLabel: "Library", articles: Array(refs)))
            }
            .task {
                if savedArticles.isEmpty && collections.isEmpty {
                    if let cached = await CompanionCache.shared.load([CompanionArticleListItem].self, category: .savedArticles) {
                        savedArticles = cached
                    }
                    await loadAll()
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCollectionSheet { newCollection in
                    collections.append(newCollection)
                }
            }
        }
    }

    // MARK: - Sections

    /// Always-visible row at the top of Library — past chat days
    /// grouped by user-local day. Briefs live inside each day's
    /// conversation now, so this is where you scroll back through
    /// what your assistant + briefs looked like.
    private var conversationHistorySection: some View {
        Section {
            NavigationLink {
                DailyConversationsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation history")
                            .font(.body)
                        Text("Briefs and chats grouped by day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
        }
    }

    /// Always-visible row at the top of Library — articles you've actually
    /// opened with foreground engagement, newest-read first. Distinct
    /// from Conversation History (per-day chats including briefs) and
    /// Saved (explicitly bookmarked).
    private var readHistorySection: some View {
        Section {
            NavigationLink {
                ReadHistoryView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading history")
                            .font(.body)
                        Text("Articles you've opened, newest first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
    }

    private var browseAllSection: some View {
        Section {
            NavigationLink {
                CompanionArticlesView(showSettings: $showSettings)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse all articles")
                            .font(.body)
                        Text("The full firehose with filters and search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "newspaper")
                }
            }
        }
    }

    private var savedSection: some View {
        Section {
            if savedArticles.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No saved articles",
                    systemImage: "bookmark",
                    description: Text("Save articles to read later.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(savedArticles) { article in
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
        } header: {
            Label("Reading List", systemImage: "bookmark.fill")
        }
    }

    private var collectionsSection: some View {
        Section {
            if collections.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No collections",
                    systemImage: "folder",
                    description: Text("Create collections to organize your articles.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(collections) { collection in
                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                    collectionRow(collection)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteCollection(collection) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                showCreateSheet = true
            } label: {
                Label("New Collection", systemImage: "plus")
            }
        } header: {
            Label("Collections", systemImage: "folder.fill")
        }
    }

    private func collectionRow(_ collection: CompanionCollection) -> some View {
        HStack {
            Image(systemName: collection.icon ?? "folder")
                .foregroundStyle(collectionColor(collection))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.body)
                if let count = collection.articleCount {
                    Text("\(count) article\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func collectionColor(_ collection: CompanionCollection) -> Color {
        guard let hex = collection.color else { return .accentColor }
        return Color(hex: hex)
    }

    // MARK: - Data

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadSaved() }
            group.addTask { await loadCollections() }
        }
    }

    private func loadSaved() async {
        do {
            let payload = try await appState.supabase.fetchArticles(saved: true)
            savedArticles = payload.articles
            errorMessage = ""
            await CompanionCache.shared.store(payload.articles, category: .savedArticles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCollections() async {
        do {
            collections = try await appState.supabase.fetchCollections()
        } catch {
            if errorMessage.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func unsaveArticle(_ article: CompanionArticleListItem) async {
        _ = await appState.syncManager?.saveArticle(articleId: article.id, saved: false)
        savedArticles.removeAll { $0.id == article.id }
        await CompanionCache.shared.store(savedArticles, category: .savedArticles)
    }

    private func deleteCollection(_ collection: CompanionCollection) async {
        do {
            try await appState.supabase.deleteCollection(id: collection.id)
            collections.removeAll { $0.id == collection.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

