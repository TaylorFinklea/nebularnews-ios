import Foundation
import SwiftData

/// An RSS, Atom, or JSON Feed source the user has subscribed to.
///
/// Feeds are polled periodically. Conditional-GET headers (`etag`, `lastModified`)
/// are persisted to avoid re-fetching unchanged content.
@Model
public final class Feed {
    public var id: String = UUID().uuidString
    public var title: String = ""
    public var feedUrl: String = ""
    public var siteUrl: String?
    public var iconUrl: String?

    // Conditional-GET headers for efficient polling
    public var etag: String?
    public var lastModified: String?

    public var lastPolledAt: Date?
    public var lastNewItemAt: Date?
    public var errorMessage: String?
    public var consecutiveErrors: Int = 0
    public var isEnabled: Bool = true
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    public var articles: [Article]? = []

    public init(feedUrl: String, title: String = "") {
        self.id = UUID().uuidString
        self.feedUrl = feedUrl
        self.title = title
        self.createdAt = Date()
    }
}
