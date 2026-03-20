import Foundation

/// A lightweight, `Sendable` snapshot of a `Feed` for crossing actor boundaries.
///
/// `@Model` objects aren't `Sendable` — they're tied to a `ModelContext` and can't
/// safely be passed between actors. `FeedSnapshot` captures feed fields without
/// pulling in SwiftData.
public struct FeedSnapshot: Sendable {
    public let id: String
    public let feedUrl: String
    public let title: String
    public let etag: String?
    public let lastModified: String?
    public let isEnabled: Bool
    public let consecutiveErrors: Int
    public let lastPolledAt: Date?

    public init(
        id: String,
        feedUrl: String,
        title: String,
        etag: String? = nil,
        lastModified: String? = nil,
        isEnabled: Bool = true,
        consecutiveErrors: Int = 0,
        lastPolledAt: Date? = nil
    ) {
        self.id = id
        self.feedUrl = feedUrl
        self.title = title
        self.etag = etag
        self.lastModified = lastModified
        self.isEnabled = isEnabled
        self.consecutiveErrors = consecutiveErrors
        self.lastPolledAt = lastPolledAt
    }
}
