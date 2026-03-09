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

    @State private var searchText = ""
    @State private var filterMode: FeedFilterMode = .unread

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                ScrollView {
                    VStack(spacing: 16) {
                        FeedFilterBar(filterMode: $filterMode, count: filteredArticles.count)
                        MagazineGrid(articles: filteredArticles)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Feed")
            .searchable(text: $searchText, prompt: "Search articles")
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
}
