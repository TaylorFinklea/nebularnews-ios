import SwiftUI
import SwiftData
import NebularNewsKit

/// Main Feed tab with magazine-style grid layout.
///
/// Articles are displayed in a score-driven magazine grid where
/// personalization scores determine visual prominence. Supports
/// filtering by read state and full-text search.
struct FeedTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var allArticles: [Article]

    @State private var navigationPath: [String] = []
    @State private var searchText = ""
    @State private var filterMode: FeedFilterMode = .unread
    @State private var reactionSheetArticleID: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            NebularScreen(emphasis: .reading) {
                ScrollView {
                    VStack(spacing: 16) {
                        FeedFilterBar(filterMode: $filterMode, count: filteredArticles.count)
                        MagazineGrid(
                            articles: filteredArticles,
                            onOpenArticle: openArticle,
                            onToggleRead: handleReadToggle,
                            onReact: presentReactionSheet
                        )
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
            .navigationTitle("Feed")
            .searchable(text: $searchText, prompt: "Search articles")
            .sheet(isPresented: isReactionSheetPresented) {
                if let article = selectedReactionArticle {
                    ReactionSheet(article: article, allowsDismiss: true)
                }
            }
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
        }
    }

    // MARK: - Filtering

    private var filteredArticles: [Article] {
        var result = allArticles

        switch filterMode {
        case .unread:
            result = result.filter(\.isUnreadQueueCandidate)
        case .all:
            break
        case .scored:
            result = result.filter(\.hasReadyScore)
        case .read:
            result = result.filter(\.isRead)
        }

        if !searchText.isEmpty {
            result = result.filter { article in
                article.title?.localizedCaseInsensitiveContains(searchText) == true ||
                article.cardSummaryText?.localizedCaseInsensitiveContains(searchText) == true ||
                article.summaryText?.localizedCaseInsensitiveContains(searchText) == true ||
                article.excerpt?.localizedCaseInsensitiveContains(searchText) == true ||
                article.author?.localizedCaseInsensitiveContains(searchText) == true ||
                article.feed?.title.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return result
    }

    private var selectedReactionArticle: Article? {
        guard let reactionSheetArticleID else { return nil }
        return allArticles.first(where: { $0.id == reactionSheetArticleID })
    }

    private var isReactionSheetPresented: Binding<Bool> {
        Binding(
            get: { selectedReactionArticle != nil },
            set: { isPresented in
                if !isPresented {
                    reactionSheetArticleID = nil
                }
            }
        )
    }

    private func handleReadToggle(for article: Article) {
        withAnimation(.snappy(duration: 0.22)) {
            if article.isRead {
                article.markUnread()
            } else {
                article.markRead()
            }
        }
        try? modelContext.save()
    }

    private func presentReactionSheet(for article: Article) {
        reactionSheetArticleID = article.id
    }

    private func openArticle(for article: Article) {
        navigationPath.append(article.id)
    }
}
