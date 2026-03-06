import Foundation

/// A parsed article from a feed, ready to be stored.
///
/// This is a pure value type (Sendable) that crosses actor boundaries safely.
/// The `FeedItemMapper` creates these from FeedKit types; the `ArticleRepository`
/// converts them into SwiftData `Article` models.
public struct ParsedArticle: Sendable {
    public let url: String?
    public let title: String?
    public let author: String?
    public let publishedAt: Date?
    public let contentHtml: String?
    public let excerpt: String?
    public let imageUrl: String?
    public let contentHash: String

    public init(
        url: String? = nil,
        title: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        contentHtml: String? = nil,
        excerpt: String? = nil,
        imageUrl: String? = nil,
        contentHash: String
    ) {
        self.url = url
        self.title = title
        self.author = author
        self.publishedAt = publishedAt
        self.contentHtml = contentHtml
        self.excerpt = excerpt
        self.imageUrl = imageUrl
        self.contentHash = contentHash
    }
}

/// Metadata extracted from the feed itself (not individual items).
public struct ParsedFeedMetadata: Sendable {
    public let title: String?
    public let siteUrl: String?
    public let iconUrl: String?

    public init(title: String? = nil, siteUrl: String? = nil, iconUrl: String? = nil) {
        self.title = title
        self.siteUrl = siteUrl
        self.iconUrl = iconUrl
    }
}
