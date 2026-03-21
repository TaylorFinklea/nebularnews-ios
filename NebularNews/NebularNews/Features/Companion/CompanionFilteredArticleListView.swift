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
                ForEach(articles) { article in
                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                        FilteredArticleRow(article: article)
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
            let payload = try await appState.mobileAPI.fetchArticles(
                offset: 0,
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

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(
                offset: articles.count,
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

private struct FilteredArticleRow: View {
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
                        image.resizable().aspectRatio(contentMode: .fill)
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
