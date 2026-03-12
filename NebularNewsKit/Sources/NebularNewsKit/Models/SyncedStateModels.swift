import Foundation
import SwiftData

@Model
public final class SyncedFeedSubscription: @unchecked Sendable {
    public var id: String = ""
    public var feedKey: String = ""
    public var feedURL: String = ""
    public var titleOverride: String?
    public var isEnabled: Bool = true
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        feedKey: String,
        feedURL: String,
        titleOverride: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = feedKey
        self.feedKey = feedKey
        self.feedURL = feedURL
        self.titleOverride = titleOverride
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class SyncedArticleState: @unchecked Sendable {
    public var id: String = ""
    public var articleKey: String = ""
    public var isRead: Bool = false
    public var readAt: Date?
    public var dismissedAt: Date?
    public var readingListAddedAt: Date?
    public var reactionValue: Int?
    public var reactionReasonCodes: String?
    public var updatedAt: Date = Date()

    public init(
        articleKey: String,
        isRead: Bool = false,
        readAt: Date? = nil,
        dismissedAt: Date? = nil,
        readingListAddedAt: Date? = nil,
        reactionValue: Int? = nil,
        reactionReasonCodes: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = articleKey
        self.articleKey = articleKey
        self.isRead = isRead
        self.readAt = readAt
        self.dismissedAt = dismissedAt
        self.readingListAddedAt = readingListAddedAt
        self.reactionValue = reactionValue
        self.reactionReasonCodes = reactionReasonCodes
        self.updatedAt = updatedAt
    }
}

@Model
public final class SyncedPreferences: @unchecked Sendable {
    public var id: String = "standalone"
    public var archiveAfterDays: Int = 13
    public var deleteArchivedAfterDays: Int = 30
    public var maxArticlesPerFeed: Int = 50
    public var searchArchivedByDefault: Bool = false
    public var updatedAt: Date = Date()

    public init(
        archiveAfterDays: Int = 13,
        deleteArchivedAfterDays: Int = 30,
        maxArticlesPerFeed: Int = 50,
        searchArchivedByDefault: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = "standalone"
        self.archiveAfterDays = archiveAfterDays
        self.deleteArchivedAfterDays = deleteArchivedAfterDays
        self.maxArticlesPerFeed = maxArticlesPerFeed
        self.searchArchivedByDefault = searchArchivedByDefault
        self.updatedAt = updatedAt
    }
}
