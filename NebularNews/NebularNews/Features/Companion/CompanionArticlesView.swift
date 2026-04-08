import SwiftUI
import NebularNewsKit

// MARK: - Companion Filter Bar

private struct CompanionFilterBar: View {
    @Binding var filter: CompanionArticleFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Status", selection: $filter.readFilter) {
                ForEach(CompanionReadFilter.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            HStack(spacing: 12) {
                Menu {
                    ForEach(CompanionSortOrder.allCases, id: \.self) { order in
                        Button {
                            filter.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.label)
                                if filter.sortOrder == order {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                } label: {
                    Label(filter.sortOrder.label, systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }

                Menu {
                    Button {
                        filter.minScore = nil
                    } label: {
                            HStack {
                                Text("Any score")
                                if filter.minScore == nil { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                    }
                    ForEach([3, 4, 5], id: \.self) { threshold in
                        Button {
                            filter.minScore = threshold
                        } label: {
                            HStack {
                                Text("\(threshold)+ score")
                                if filter.minScore == threshold { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                        }
                    }
                } label: {
                    Label(filter.minScore.map { "\($0)+" } ?? "Score", systemImage: "star")
                        .font(.caption)
                }

                Spacer()

                if filter.isActive {
                    Button("Clear") {
                        withAnimation { filter.reset() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

// MARK: - Articles

struct CompanionArticlesView: View {
    @Environment(AppState.self) private var appState

    @Binding var showSettings: Bool

    @State private var query = ""
    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var filter = CompanionArticleFilter()
    @State private var recentSearches: [String] = {
        UserDefaults.standard.stringArray(forKey: "companionRecentSearches") ?? []
    }()

    private var hasMore: Bool { articles.count < total }

    var body: some View {
        NavigationStack {
            List {
                if appState.syncManager?.isOffline == true {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .accessibilityHidden(true)
                            Text("Offline")
                            if let count = appState.syncManager?.pendingActionCount, count > 0 {
                                Text("• \(count) pending")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    }
                }

                if !errorMessage.isEmpty && articles.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage) {
                            Task { await loadArticles() }
                        }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    CompanionFilterBar(filter: $filter)
                        .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    if articles.isEmpty && !isLoading && errorMessage.isEmpty {
                        ContentUnavailableView(
                            "No articles",
                            systemImage: "doc.text",
                            description: Text(filter.isActive ? "No articles match your filters." : "Articles will appear here once your feeds are polled.")
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
                                Label(article.isReadBool ? "Unread" : "Read", systemImage: article.isReadBool ? "eye" : "eye.slash")
                            }
                            .tint(article.isReadBool ? .blue : .gray)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await react(article, value: 1) }
                            } label: {
                                Label("Like", systemImage: "hand.thumbsup")
                            }
                            .tint(.green)
                            Button {
                                Task { await react(article, value: -1) }
                            } label: {
                                Label("Dislike", systemImage: "hand.thumbsdown")
                            }
                            .tint(.red)
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
                                    .onAppear {
                                        Task { await loadMoreArticles() }
                                    }
                            }
                            Spacer()
                        }
                    }
                }

                if !errorMessage.isEmpty && !articles.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage) {
                            Task { await loadMoreArticles() }
                        }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .overlay {
                if isLoading && articles.isEmpty {
                    ProgressView("Loading articles…")
                }
            }
            .navigationTitle("Articles")
            .toolbar {
                ToolbarItem(placement: .platformTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear").accessibilityLabel("Settings") }
                }
            }
            .searchable(text: $query, prompt: "Search articles")
            .searchSuggestions {
                if query.isEmpty && !recentSearches.isEmpty {
                    ForEach(recentSearches, id: \.self) { recent in
                        Text(recent)
                            .searchCompletion(recent)
                    }
                }
            }
            .onSubmit(of: .search) {
                saveRecentSearch(query)
            }
            .task(id: FilterKey(query: query, filter: filter)) {
                await loadArticles()
            }
            .refreshable {
                try? await appState.supabase.triggerPull()
                try? await Task.sleep(for: .seconds(2))
                await loadArticles()
            }
        }
    }

    private func loadArticles() async {
        // Show cached data instantly while network request is in flight
        if articles.isEmpty, let cache = appState.articleCache {
            let cached = cache.getCachedArticles(
                readFilter: filter.readFilter,
                minScore: filter.minScore,
                sortOrder: filter.sortOrder,
                query: query
            )
            if !cached.isEmpty {
                articles = ArticleCache.toListItems(cached)
                total = cached.count
            }
        }

        isLoading = articles.isEmpty
        defer { isLoading = false }

        do {
            let payload: CompanionArticlesPayload
            if let cache = appState.articleCache {
                payload = try await cache.syncArticles(
                    from: appState.supabase,
                    query: query,
                    read: filter.readFilter,
                    minScore: filter.minScore,
                    sort: filter.sortOrder
                )
            } else {
                payload = try await appState.supabase.fetchArticles(
                    query: query,
                    offset: 0,
                    limit: PaginationConfig.companionPageSize,
                    read: filter.readFilter,
                    minScore: filter.minScore,
                    sort: filter.sortOrder
                )
            }
            articles = payload.articles
            total = payload.total
            errorMessage = ""
        } catch {
            // Keep showing cached data on error
            if articles.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Offline — showing cached articles"
            }
        }
    }

    private func loadMoreArticles() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload: CompanionArticlesPayload
            if let cache = appState.articleCache {
                payload = try await cache.syncArticles(
                    from: appState.supabase,
                    query: query,
                    read: filter.readFilter,
                    minScore: filter.minScore,
                    sort: filter.sortOrder,
                    offset: articles.count
                )
            } else {
                payload = try await appState.supabase.fetchArticles(
                    query: query,
                    offset: articles.count,
                    limit: PaginationConfig.companionPageSize,
                    read: filter.readFilter,
                    minScore: filter.minScore,
                    sort: filter.sortOrder
                )
            }
            articles.append(contentsOf: payload.articles)
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRead(_ article: CompanionArticleListItem) async {
        let newReadState = article.isRead != 1
        await appState.syncManager?.setRead(articleId: article.id, isRead: newReadState)
        await loadArticles()
    }

    private func react(_ article: CompanionArticleListItem, value: Int) async {
        _ = await appState.syncManager?.setReaction(
            articleId: article.id,
            value: value,
            reasonCodes: []
        )
    }

    private func saveRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        UserDefaults.standard.set(recentSearches, forKey: "companionRecentSearches")
    }
}

private struct FilterKey: Equatable {
    let query: String
    let filter: CompanionArticleFilter
}
