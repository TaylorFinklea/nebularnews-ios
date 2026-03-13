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

#if DEBUG
public struct StandaloneSyncDebugPreferences: Sendable {
    public let archiveAfterDays: Int
    public let deleteArchivedAfterDays: Int
    public let maxArticlesPerFeed: Int
    public let searchArchivedByDefault: Bool
    public let updatedAt: Date

    public init(
        archiveAfterDays: Int,
        deleteArchivedAfterDays: Int,
        maxArticlesPerFeed: Int,
        searchArchivedByDefault: Bool,
        updatedAt: Date
    ) {
        self.archiveAfterDays = archiveAfterDays
        self.deleteArchivedAfterDays = deleteArchivedAfterDays
        self.maxArticlesPerFeed = maxArticlesPerFeed
        self.searchArchivedByDefault = searchArchivedByDefault
        self.updatedAt = updatedAt
    }
}

public struct StandaloneSyncDebugFeedRow: Identifiable, Sendable {
    public let id: String
    public let feedKey: String
    public let feedURL: String
    public let titleOverride: String?
    public let isEnabled: Bool
    public let updatedAt: Date

    public init(
        id: String,
        feedKey: String,
        feedURL: String,
        titleOverride: String?,
        isEnabled: Bool,
        updatedAt: Date
    ) {
        self.id = id
        self.feedKey = feedKey
        self.feedURL = feedURL
        self.titleOverride = titleOverride
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }
}

public struct StandaloneSyncDebugArticleStateRow: Identifiable, Sendable {
    public let id: String
    public let articleKey: String
    public let isRead: Bool
    public let isDismissed: Bool
    public let isSaved: Bool
    public let reactionValue: Int?
    public let updatedAt: Date

    public init(
        id: String,
        articleKey: String,
        isRead: Bool,
        isDismissed: Bool,
        isSaved: Bool,
        reactionValue: Int?,
        updatedAt: Date
    ) {
        self.id = id
        self.articleKey = articleKey
        self.isRead = isRead
        self.isDismissed = isDismissed
        self.isSaved = isSaved
        self.reactionValue = reactionValue
        self.updatedAt = updatedAt
    }
}

public struct StandaloneSyncDebugSnapshot: Sendable {
    public let syncedFeedSubscriptionCount: Int
    public let syncedArticleStateCount: Int
    public let localFeedCount: Int
    public let localArticleCount: Int
    public let localReadCount: Int
    public let localDismissedCount: Int
    public let localSavedCount: Int
    public let localReactedCount: Int
    public let syncedPreferences: StandaloneSyncDebugPreferences?
    public let feedRows: [StandaloneSyncDebugFeedRow]
    public let articleStateRows: [StandaloneSyncDebugArticleStateRow]

    public init(
        syncedFeedSubscriptionCount: Int,
        syncedArticleStateCount: Int,
        localFeedCount: Int,
        localArticleCount: Int,
        localReadCount: Int,
        localDismissedCount: Int,
        localSavedCount: Int,
        localReactedCount: Int,
        syncedPreferences: StandaloneSyncDebugPreferences?,
        feedRows: [StandaloneSyncDebugFeedRow],
        articleStateRows: [StandaloneSyncDebugArticleStateRow]
    ) {
        self.syncedFeedSubscriptionCount = syncedFeedSubscriptionCount
        self.syncedArticleStateCount = syncedArticleStateCount
        self.localFeedCount = localFeedCount
        self.localArticleCount = localArticleCount
        self.localReadCount = localReadCount
        self.localDismissedCount = localDismissedCount
        self.localSavedCount = localSavedCount
        self.localReactedCount = localReactedCount
        self.syncedPreferences = syncedPreferences
        self.feedRows = feedRows
        self.articleStateRows = articleStateRows
    }
}
#endif
