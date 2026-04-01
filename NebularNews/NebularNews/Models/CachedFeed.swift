import Foundation
import SwiftData

@Model
final class CachedFeed {
    @Attribute(.unique) var id: String
    var url: String = ""
    var title: String?
    var siteUrl: String?
    var articleCount: Int = 0
    var errorCount: Int = 0
    var paused: Bool = false
    var maxArticlesPerDay: Int?
    var minScore: Int?
    var cachedAt: Date = Date()

    init(id: String) {
        self.id = id
    }
}
