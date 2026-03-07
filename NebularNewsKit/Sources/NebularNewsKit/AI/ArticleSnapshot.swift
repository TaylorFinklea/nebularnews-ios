import Foundation

/// A lightweight, `Sendable` snapshot of an `Article` for AI processing.
///
/// Follows the same pattern as `FeedSnapshot` — `@Model` objects can't cross
/// actor boundaries, so we copy the fields the `AIEnrichmentService` needs
/// into a plain struct.
public struct ArticleSnapshot: Sendable {
    public let id: String
    public let title: String?
    public let contentText: String  // HTML stripped to plain text
    public let canonicalUrl: String?
    public let feedTitle: String?

    public init(
        id: String,
        title: String?,
        contentText: String,
        canonicalUrl: String? = nil,
        feedTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.contentText = contentText
        self.canonicalUrl = canonicalUrl
        self.feedTitle = feedTitle
    }
}
