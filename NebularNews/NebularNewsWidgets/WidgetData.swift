import Foundation

// MARK: - Shared data types for App ↔ Widget communication
//
// These Codable structs live in the widget target and are mirrored by
// the encoding logic in the main app (WidgetDataWriter). They must stay
// in sync — any field added here must also be written in WidgetDataWriter.

enum WidgetData {
    static let suiteName = "group.com.nebularnews.shared"

    // UserDefaults keys
    static let statsKey = "widget_stats"
    static let topArticlesKey = "widget_top_articles"
    static let lastUpdatedKey = "widget_last_updated"
}

struct WidgetStats: Codable {
    let unreadTotal: Int
    let newToday: Int
    let highFitUnread: Int
}

struct WidgetArticle: Codable, Identifiable {
    let id: String
    let title: String
    let score: Int?
    let feedName: String?
    let excerpt: String?
}
