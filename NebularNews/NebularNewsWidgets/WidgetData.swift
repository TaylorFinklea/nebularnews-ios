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
    static let briefKey = "widget_brief"
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

struct WidgetBrief: Codable {
    let id: String?            // brief edition id; absent on older cached data
    let title: String          // e.g. "Morning Brief"
    let editionLabel: String   // "Morning" or "Evening"
    let generatedAt: Double?   // epoch seconds
    let bullets: [String]      // pre-flattened bullet text; widget shouldn't parse sources
}
