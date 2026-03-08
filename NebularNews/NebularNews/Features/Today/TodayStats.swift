import Foundation
import NebularNewsKit

/// Computed stats for the Today briefing, extracted from @Query results.
struct TodayStats {
    let unreadCount: Int
    let newToday: Int
    let newThisWeek: Int
    let highFit: Int
    let scoredCount: Int
    let learningCount: Int
    let feedCount: Int
    let totalArticles: Int

    static func compute(articles: [Article], feedCount: Int) -> TodayStats {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)
        let weekAgo = now.addingTimeInterval(-604_800)

        return TodayStats(
            unreadCount: articles.count(where: \.isUnreadQueueCandidate),
            newToday: articles.count(where: {
                $0.isUnreadQueueCandidate && ($0.publishedAt ?? .distantPast) > dayAgo
            }),
            newThisWeek: articles.count(where: {
                $0.isUnreadQueueCandidate && ($0.publishedAt ?? .distantPast) > weekAgo
            }),
            highFit: articles.count(where: {
                $0.isUnreadQueueCandidate &&
                $0.hasReadyScore &&
                ($0.score ?? 0) >= 4 &&
                ($0.publishedAt ?? .distantPast) > weekAgo
            }),
            scoredCount: articles.count(where: \.hasReadyScore),
            learningCount: articles.count(where: \.isLearningScore),
            feedCount: feedCount,
            totalArticles: articles.count
        )
    }
}
