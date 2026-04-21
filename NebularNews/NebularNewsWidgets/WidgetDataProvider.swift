import Foundation

/// Reads widget data from the shared App Group container.
///
/// The main app writes stats and article data to a shared UserDefaults
/// suite after each data fetch. This provider reads that cached data
/// for use in widget timeline entries.
enum WidgetDataProvider {

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetData.suiteName)
    }

    // MARK: - Stats

    static func loadStats() -> WidgetStats {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: WidgetData.statsKey),
              let stats = try? JSONDecoder().decode(WidgetStats.self, from: data) else {
            return WidgetStats(unreadTotal: 0, newToday: 0, highFitUnread: 0)
        }
        return stats
    }

    // MARK: - Articles

    static func loadTopArticles(limit: Int = 5) -> [WidgetArticle] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: WidgetData.topArticlesKey),
              let articles = try? JSONDecoder().decode([WidgetArticle].self, from: data) else {
            return []
        }
        return Array(articles.prefix(limit))
    }

    // MARK: - News Brief

    static func loadBrief() -> WidgetBrief? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: WidgetData.briefKey),
              let brief = try? JSONDecoder().decode(WidgetBrief.self, from: data) else {
            return nil
        }
        return brief
    }

    // MARK: - Freshness

    static func lastUpdated() -> Date? {
        guard let defaults = sharedDefaults else { return nil }
        let interval = defaults.double(forKey: WidgetData.lastUpdatedKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}
