import Foundation

enum PerFeedDailyCapFilter {
    /// Drop articles past each feed's `max_articles_per_day` cap, per calendar day
    /// in the device's timezone. Pure client-side: backend behavior is unaffected.
    ///
    /// `caps` maps feed id → max per day. Feeds missing from the map (or with cap
    /// ≤ 0) are treated as unlimited. Articles without a `sourceFeedId` are
    /// always passed through.
    ///
    /// Input order is preserved: within each (feed, day) bucket the first N
    /// articles win, so callers should sort newest-first before applying.
    static func apply(
        _ articles: [CompanionArticleListItem],
        caps: [String: Int],
        calendar: Calendar = .current
    ) -> [CompanionArticleListItem] {
        guard !caps.isEmpty else { return articles }

        var perBucketCount: [String: Int] = [:]
        var result: [CompanionArticleListItem] = []
        result.reserveCapacity(articles.count)

        for article in articles {
            guard let feedId = article.sourceFeedId,
                  let cap = caps[feedId], cap > 0,
                  let timestampMs = article.publishedAt ?? article.fetchedAt else {
                result.append(article)
                continue
            }

            let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
            let day = calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
            let key = "\(feedId)|\(day)"

            let count = perBucketCount[key, default: 0]
            if count < cap {
                perBucketCount[key] = count + 1
                result.append(article)
            }
        }

        return result
    }
}
