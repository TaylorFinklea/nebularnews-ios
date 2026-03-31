import SwiftUI
import NebularNewsKit

/// Article list with score badges, summary previews, and filter controls.
///
/// Ported from the standalone-era `ArticleListView`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData `@Query`.
struct ArticleListView: View {
    @Environment(AppState.self) private var appState

    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var searchText = ""
    @State private var filter = CompanionArticleFilter()
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage = ""

    /// Optional feed filter -- when set, only shows articles from this feed.
    let feedId: String?
    let feedTitle: String?

    init(feedId: String? = nil, feedTitle: String? = nil) {
        self.feedId = feedId
        self.feedTitle = feedTitle
    }

    private var hasMore: Bool { articles.count < total }

    var body: some View {
        NavigationStack {
            Group {
                if articles.isEmpty && !isLoading && errorMessage.isEmpty {
                    ContentUnavailableView(
                        "No Articles Yet",
                        systemImage: "doc.text",
                        description: Text("Add some feeds and pull to refresh.")
                    )
                } else {
                    List {
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage) {
                                Task { await load() }
                            }
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                        }

                        ForEach(articles) { article in
                            NavigationLink(destination: ArticleDetailView(articleId: article.id)) {
                                ArticleRow(article: article)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await toggleRead(article) }
                                } label: {
                                    Label(
                                        article.isRead == 1 ? "Unread" : "Read",
                                        systemImage: article.isRead == 1 ? "envelope.badge" : "envelope.open"
                                    )
                                }
                                .tint(article.isRead == 1 ? .blue : .green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    Task { await toggleSaved(article) }
                                } label: {
                                    Label("Save", systemImage: "bookmark")
                                }
                                .tint(.orange)
                            }
                        }

                        if hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                                .task { await loadMore() }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(feedTitle ?? "Articles")
            .searchable(text: $searchText, prompt: "Search articles")
            .overlay {
                if isLoading && articles.isEmpty {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Status", selection: Binding(
                            get: { filter.readFilter },
                            set: { newValue in
                                filter.readFilter = newValue
                                Task { await load() }
                            }
                        )) {
                            ForEach(CompanionReadFilter.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }

                        Divider()

                        Menu("Sort") {
                            ForEach(CompanionSortOrder.allCases, id: \.self) { order in
                                Button {
                                    filter.sortOrder = order
                                    Task { await load() }
                                } label: {
                                    HStack {
                                        Text(order.label)
                                        if filter.sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }

                        Menu("Min Score") {
                            Button {
                                filter.minScore = nil
                                Task { await load() }
                            } label: {
                                HStack {
                                    Text("Any")
                                    if filter.minScore == nil { Image(systemName: "checkmark") }
                                }
                            }
                            ForEach([3, 4, 5], id: \.self) { threshold in
                                Button {
                                    filter.minScore = threshold
                                    Task { await load() }
                                } label: {
                                    HStack {
                                        Text("\(threshold)+")
                                        if filter.minScore == threshold { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }

                        if filter.isActive {
                            Divider()
                            Button("Reset Filters") {
                                filter.reset()
                                Task { await load() }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(articles.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .refreshable {
                await load()
            }
            .task {
                if articles.isEmpty {
                    await load()
                }
            }
            .onChange(of: searchText) { _, _ in
                Task {
                    // Debounce slightly
                    try? await Task.sleep(for: .milliseconds(300))
                    await load()
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = ""

        do {
            let readFilter: ReadFilter = switch filter.readFilter {
            case .all: .all
            case .unread: .unread
            case .read: .read
            }

            let sortOrder: SortOrder = switch filter.sortOrder {
            case .newest: .newest
            case .oldest: .oldest
            case .score: .score
            case .unreadFirst: .unreadFirst
            }

            let payload = try await appState.supabase.fetchArticles(
                query: searchText,
                offset: 0,
                limit: 30,
                read: readFilter,
                minScore: filter.minScore,
                sort: sortOrder
            )
            articles = payload.articles
            total = payload.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let readFilter: ReadFilter = switch filter.readFilter {
            case .all: .all
            case .unread: .unread
            case .read: .read
            }

            let sortOrder: SortOrder = switch filter.sortOrder {
            case .newest: .newest
            case .oldest: .oldest
            case .score: .score
            case .unreadFirst: .unreadFirst
            }

            let payload = try await appState.supabase.fetchArticles(
                query: searchText,
                offset: articles.count,
                limit: 30,
                read: readFilter,
                minScore: filter.minScore,
                sort: sortOrder
            )
            articles.append(contentsOf: payload.articles)
            total = payload.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRead(_ article: CompanionArticleListItem) async {
        let newIsRead = article.isRead != 1
        do {
            try await appState.supabase.setRead(articleId: article.id, isRead: newIsRead)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSaved(_ article: CompanionArticleListItem) async {
        do {
            _ = try await appState.supabase.saveArticle(id: article.id, saved: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Article Row

private struct ArticleRow: View {
    let article: CompanionArticleListItem

    private var isRead: Bool { article.isRead == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Feed name + date + score
            HStack {
                if let source = article.sourceName, !source.isEmpty {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                if let score = article.score {
                    ScoreBadge(score: score)
                }

                if let publishedAt = article.publishedAt {
                    Text(Date(timeIntervalSince1970: Double(publishedAt) / 1000).relativeDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Title
            Text(article.title ?? "Untitled")
                .font(.headline)
                .fontWeight(isRead ? .regular : .semibold)
                .foregroundStyle(isRead ? .secondary : .primary)
                .lineLimit(2)

            // Summary or excerpt preview
            if let summary = article.summaryText, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let excerpt = article.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Author
            if let author = article.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isRead ? 0.7 : 1)
    }
}
