import Foundation
import WidgetKit
import os

/// Writes widget data to the shared App Group container after each data fetch.
///
/// The main app calls `updateStats` and `updateTopArticles` whenever
/// the Today view or article list refreshes. The widget extension reads
/// this data via `WidgetDataProvider` from the same UserDefaults suite.
enum WidgetDataWriter {

    private static let logger = Logger(subsystem: "com.nebularnews", category: "WidgetDataWriter")

    static let suiteName = "group.com.nebularnews.shared"

    // UserDefaults keys — must match the widget's WidgetData constants
    private static let statsKey = "widget_stats"
    private static let topArticlesKey = "widget_top_articles"
    private static let briefKey = "widget_brief"
    private static let lastUpdatedKey = "widget_last_updated"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Stats

    /// Write today's stats for the stats widget.
    static func updateStats(unreadTotal: Int, newToday: Int, highFitUnread: Int) {
        guard let defaults = sharedDefaults else {
            logger.warning("Could not open shared UserDefaults suite")
            return
        }

        struct Stats: Codable {
            let unreadTotal: Int
            let newToday: Int
            let highFitUnread: Int
        }

        let stats = Stats(unreadTotal: unreadTotal, newToday: newToday, highFitUnread: highFitUnread)
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: statsKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)
            logger.debug("Widget stats updated: \(unreadTotal) unread, \(newToday) new, \(highFitUnread) high-fit")
        }

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadTimelines(ofKind: "StatsWidget")
    }

    // MARK: - Top Articles

    /// Write the top-scored unread articles for the article widgets.
    static func updateTopArticles(_ articles: [ArticleWidgetData]) {
        guard let defaults = sharedDefaults else {
            logger.warning("Could not open shared UserDefaults suite")
            return
        }

        if let data = try? JSONEncoder().encode(articles) {
            defaults.set(data, forKey: topArticlesKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)
            logger.debug("Widget articles updated: \(articles.count) articles")
        }

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadTimelines(ofKind: "TopArticleWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ReadingQueueWidget")
    }

    // MARK: - News Brief

    /// Write the latest news brief for the brief widget.
    static func updateBrief(_ brief: BriefWidgetData?) {
        guard let defaults = sharedDefaults else {
            logger.warning("Could not open shared UserDefaults suite")
            return
        }

        if let brief, let data = try? JSONEncoder().encode(brief) {
            defaults.set(data, forKey: briefKey)
            defaults.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)
            logger.debug("Widget brief updated: \(brief.bullets.count) bullets")
        } else {
            defaults.removeObject(forKey: briefKey)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "NewsBriefWidget")
    }

    // MARK: - Convenience

    /// Write stats, articles, and brief from a today payload.
    static func updateFromToday(
        stats: CompanionTodayStats,
        hero: CompanionArticleListItem?,
        upNext: [CompanionArticleListItem],
        newsBrief: CompanionNewsBrief? = nil
    ) {
        // Stats
        updateStats(
            unreadTotal: stats.unreadTotal,
            newToday: stats.newToday,
            highFitUnread: stats.highFitUnread
        )

        // Articles: hero first, then up-next, sorted by score descending
        var allArticles: [CompanionArticleListItem] = []
        if let hero { allArticles.append(hero) }
        allArticles.append(contentsOf: upNext)

        // Deduplicate (hero might also be in upNext)
        var seen = Set<String>()
        let unique = allArticles.filter { seen.insert($0.id).inserted }

        // Sort by score descending, then take top 10
        let sorted = unique.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let widgetArticles = Array(sorted.prefix(10)).map { article in
            ArticleWidgetData(
                id: article.id,
                title: article.title ?? "Untitled",
                score: article.score,
                feedName: article.sourceName,
                excerpt: article.excerpt
            )
        }

        updateTopArticles(widgetArticles)

        // Brief (optional — absent when today payload has no persisted brief).
        if let newsBrief, newsBrief.state == "done", !newsBrief.bullets.isEmpty {
            let briefData = BriefWidgetData(
                id: newsBrief.id,
                title: newsBrief.title,
                editionLabel: newsBrief.editionLabel,
                generatedAt: newsBrief.generatedAt.map { Double($0) / 1000 },
                bullets: newsBrief.bullets.map(\.text)
            )
            updateBrief(briefData)
        } else {
            updateBrief(nil)
        }
    }
}

/// Lightweight Codable for the brief widget. Must encode to the same shape as
/// the widget's `WidgetBrief`.
struct BriefWidgetData: Codable {
    let id: String?
    let title: String
    let editionLabel: String
    let generatedAt: Double?
    let bullets: [String]
}

/// Lightweight Codable struct for passing article data to widgets.
/// Must encode to the same shape as the widget's `WidgetArticle`.
struct ArticleWidgetData: Codable {
    let id: String
    let title: String
    let score: Int?
    let feedName: String?
    let excerpt: String?
}
