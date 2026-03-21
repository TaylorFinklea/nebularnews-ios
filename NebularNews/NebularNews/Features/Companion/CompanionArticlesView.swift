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
                            if filter.minScore == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach([3, 4, 5], id: \.self) { threshold in
                        Button {
                            filter.minScore = threshold
                        } label: {
                            HStack {
                                Text("\(threshold)+ score")
                                if filter.minScore == threshold { Image(systemName: "checkmark") }
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
                    ForEach(articles) { article in
                        NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                            ArticleRow(article: article)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
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
                _ = try? await appState.mobileAPI.triggerPull()
                try? await Task.sleep(for: .seconds(2))
                await loadArticles()
            }
        }
    }

    private func loadArticles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(
                query: query,
                offset: 0,
                read: filter.readFilter,
                minScore: filter.minScore,
                sort: filter.sortOrder
            )
            articles = payload.articles
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreArticles() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(
                query: query,
                offset: articles.count,
                read: filter.readFilter,
                minScore: filter.minScore,
                sort: filter.sortOrder
            )
            articles.append(contentsOf: payload.articles)
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
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

// MARK: - Article Row

private struct ArticleRow: View {
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
                    if article.isRead == 1 {
                        Text("Read")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color(.tertiarySystemFill)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 2)
    }
}
