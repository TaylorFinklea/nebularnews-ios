import Foundation

/// Context sent to the AI assistant describing the current page and its data.
struct AIPageContext: Codable, Equatable {
    let pageType: String
    let pageLabel: String
    var articles: [AIArticleRef]?
    var articleDetail: AIArticleDetail?
    var stats: AIPageStats?
    var filters: [String: String]?
    var tags: [String]?
    var feeds: [AIFeedRef]?
    var briefSummary: String?
}

struct AIArticleRef: Codable, Equatable {
    let id: String
    let title: String
    var score: Int?
    var source: String?
    var date: String?
    var isRead: Bool?
}

struct AIArticleDetail: Codable, Equatable {
    let articleId: String
    let title: String
    var summary: String?
    var keyPoints: [String]?
    var score: Int?
    var tags: [String]?
    var contentExcerpt: String?
}

struct AIPageStats: Codable, Equatable {
    var unreadCount: Int?
    var totalCount: Int?
    var newToday: Int?
}

struct AIFeedRef: Codable, Equatable {
    let id: String
    let title: String
    var articleCount: Int?
    var isPaused: Bool?
}
