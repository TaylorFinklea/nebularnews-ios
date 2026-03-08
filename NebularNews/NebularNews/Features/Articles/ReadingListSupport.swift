import Foundation
import NebularNewsKit

enum ReadingListFilterMode: String, CaseIterable, Sendable {
    case all = "All"
    case unread = "Unread"
    case read = "Read"
}

enum ReadingListContent {
    nonisolated static func filteredArticles(
        from articles: [Article],
        searchText: String,
        filterMode: ReadingListFilterMode
    ) -> [Article] {
        var result = articles

        switch filterMode {
        case .all:
            break
        case .unread:
            result = result.filter { !$0.isRead }
        case .read:
            result = result.filter(\.isRead)
        }

        if !searchText.isEmpty {
            result = result.filter { article in
                article.title?.localizedCaseInsensitiveContains(searchText) == true ||
                article.excerpt?.localizedCaseInsensitiveContains(searchText) == true ||
                article.author?.localizedCaseInsensitiveContains(searchText) == true ||
                article.feed?.title.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return result.sorted(by: sortSavedArticles)
    }

    private nonisolated static func sortSavedArticles(_ lhs: Article, _ rhs: Article) -> Bool {
        let leftSavedAt = lhs.readingListAddedAt ?? .distantPast
        let rightSavedAt = rhs.readingListAddedAt ?? .distantPast

        if leftSavedAt != rightSavedAt {
            return leftSavedAt > rightSavedAt
        }

        return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
    }
}
