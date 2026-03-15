import Foundation
import SwiftData

@ModelActor
public actor StandaloneStateSyncService {
    public func bootstrap() async {
        let didUpdateIdentities = ensureLocalIdentities()
        let didSeedPreferences = seedSyncedPreferencesFromLocalIfNeeded()
        let didSeedFeeds = seedSyncedFeedSubscriptionsFromLocalIfNeeded()
        let didSeedArticleStates = seedSyncedArticleStatesFromLocalIfNeeded()
        let didBackfillArticleStateFeedKeys = backfillSyncedArticleStateFeedKeys()

        let didApplyPreferences = applySyncedPreferencesToLocal()
        let didProjectFeeds = reconcileLocalFeedsWithSyncedSubscriptions()
        let didProjectArticles = applySyncedArticleStatesToLocalArticles()

        if didUpdateIdentities || didSeedPreferences || didSeedFeeds || didSeedArticleStates || didBackfillArticleStateFeedKeys || didApplyPreferences || didProjectFeeds || didProjectArticles {
            try? modelContext.save()
        }

        if didProjectArticles {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            await articleRepo.rebuildTodaySnapshot()
            ArticleChangeBus.postFeedPageMightChange()
            ArticleChangeBus.postReadingListChanged()
        }
    }

    public func pushLocalPreferences() async {
        guard let settings = currentSettings() else {
            return
        }

        let updatedAt = settings.updatedAt
        upsertSyncedPreferences(from: settings, updatedAt: updatedAt)
        settings.syncedPreferencesUpdatedAt = updatedAt
        try? modelContext.save()
    }

    public func pushLocalArticleState(articleID: String) async {
        guard let article = localArticle(id: articleID) else {
            return
        }

        article.refreshQueryState()
        guard !article.articleKey.isEmpty else {
            try? modelContext.save()
            return
        }

        upsertSyncedArticleState(from: article, updatedAt: article.userStateUpdatedAt ?? Date())
        try? modelContext.save()
    }

    private func currentSettings() -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        guard let settings = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        if settings.normalizeStorageSettings() {
            settings.updatedAt = Date()
        }
        return settings
    }

    private func localArticle(id: String) -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func ensureLocalIdentities() -> Bool {
        let feeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        let articles = (try? modelContext.fetch(FetchDescriptor<Article>())) ?? []
        var didChange = false

        for feed in feeds {
            let previousKey = feed.feedKey
            let previousURL = feed.feedUrl
            feed.refreshIdentity()
            if feed.feedKey != previousKey || feed.feedUrl != previousURL {
                didChange = true
            }
        }

        for article in articles {
            let previousKey = article.articleKey
            article.refreshQueryState()
            if article.articleKey != previousKey {
                didChange = true
            }
        }

        return didChange
    }

    private func seedSyncedPreferencesFromLocalIfNeeded() -> Bool {
        guard let settings = currentSettings() else {
            return false
        }

        guard syncedPreferences() == nil else {
            return false
        }

        let updatedAt = settings.syncedPreferencesUpdatedAt ?? settings.updatedAt
        upsertSyncedPreferences(from: settings, updatedAt: updatedAt)
        settings.syncedPreferencesUpdatedAt = updatedAt
        return true
    }

    private func applySyncedPreferencesToLocal() -> Bool {
        guard let synced = syncedPreferences(),
              let settings = currentSettings()
        else {
            return false
        }

        if let localSyncedAt = settings.syncedPreferencesUpdatedAt,
           localSyncedAt > synced.updatedAt {
            upsertSyncedPreferences(from: settings, updatedAt: localSyncedAt)
            return true
        }

        if settings.syncedPreferencesUpdatedAt == nil || synced.updatedAt > (settings.syncedPreferencesUpdatedAt ?? .distantPast) {
            settings.archiveAfterDays = synced.archiveAfterDays
            settings.retentionDays = synced.archiveAfterDays
            settings.deleteArchivedAfterDays = synced.deleteArchivedAfterDays
            settings.searchArchivedByDefault = synced.searchArchivedByDefault
            settings.maxArticlesPerFeed = synced.maxArticlesPerFeed
            _ = settings.normalizeStorageSettings()
            settings.syncedPreferencesUpdatedAt = synced.updatedAt
            settings.updatedAt = max(settings.updatedAt, synced.updatedAt)
            return true
        }

        return false
    }

    private func seedSyncedFeedSubscriptionsFromLocalIfNeeded() -> Bool {
        let feeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        var didChange = false

        for feed in feeds {
            feed.refreshIdentity()
            guard !feed.feedKey.isEmpty else {
                continue
            }

            if syncedFeedSubscription(feedKey: feed.feedKey) == nil {
                let titleOverride = feed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : feed.title
                modelContext.insert(
                    SyncedFeedSubscription(
                        feedKey: feed.feedKey,
                        feedURL: feed.feedUrl,
                        titleOverride: titleOverride,
                        isEnabled: feed.isEnabled,
                        createdAt: feed.createdAt,
                        updatedAt: feed.createdAt
                    )
                )
                didChange = true
            }
        }

        return didChange
    }

    private func reconcileLocalFeedsWithSyncedSubscriptions() -> Bool {
        let syncedFeeds = (try? modelContext.fetch(FetchDescriptor<SyncedFeedSubscription>())) ?? []
        let localFeeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []

        var localByKey: [String: Feed] = [:]
        for feed in localFeeds {
            feed.refreshIdentity()
            if !feed.feedKey.isEmpty {
                localByKey[feed.feedKey] = feed
            }
        }

        var didChange = false

        for synced in syncedFeeds {
            let canonicalURL = canonicalFeedURLForStorage(synced.feedURL) ?? synced.feedURL
            if let local = localByKey[synced.feedKey] {
                if local.feedUrl != canonicalURL {
                    local.feedUrl = canonicalURL
                    didChange = true
                }
                if local.feedKey != synced.feedKey {
                    local.feedKey = synced.feedKey
                    didChange = true
                }
                if local.isEnabled != synced.isEnabled {
                    local.isEnabled = synced.isEnabled
                    didChange = true
                }
                if let titleOverride = synced.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !titleOverride.isEmpty,
                   local.title != titleOverride {
                    local.title = titleOverride
                    didChange = true
                }
            } else {
                let feed = Feed(feedUrl: canonicalURL, title: synced.titleOverride ?? "")
                feed.feedKey = synced.feedKey
                feed.isEnabled = synced.isEnabled
                feed.createdAt = synced.createdAt
                modelContext.insert(feed)
                didChange = true
            }
        }

        let syncedKeys = Set(syncedFeeds.map(\.feedKey))
        for feed in localFeeds where !feed.feedKey.isEmpty && !syncedKeys.contains(feed.feedKey) {
            modelContext.delete(feed)
            didChange = true
        }

        return didChange
    }

    private func seedSyncedArticleStatesFromLocalIfNeeded() -> Bool {
        let descriptor = FetchDescriptor<Article>()
        let localArticles = (try? modelContext.fetch(descriptor)) ?? []
        var didChange = false

        for article in localArticles {
            article.refreshQueryState()
            guard !article.articleKey.isEmpty,
                  let updatedAt = article.userStateUpdatedAt
            else {
                continue
            }

            if let existing = syncedArticleState(articleKey: article.articleKey) {
                if updatedAt > existing.updatedAt {
                    upsertSyncedArticleState(from: article, updatedAt: updatedAt)
                    didChange = true
                }
            } else {
                upsertSyncedArticleState(from: article, updatedAt: updatedAt)
                didChange = true
            }
        }

        return didChange
    }

    private func backfillSyncedArticleStateFeedKeys() -> Bool {
        let syncedStates = (try? modelContext.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
        let localArticles = (try? modelContext.fetch(FetchDescriptor<Article>())) ?? []
        let localFeedKeyByArticleKey: [String: String] = Dictionary(
            uniqueKeysWithValues: localArticles.compactMap { article -> (String, String)? in
                article.refreshQueryState()
                guard !article.articleKey.isEmpty,
                      let feedKey = article.feed?.feedKey,
                      !feedKey.isEmpty
                else {
                    return nil
                }
                return (article.articleKey, feedKey)
            }
        )

        var didChange = false
        for synced in syncedStates where synced.feedKey.isEmpty {
            guard let feedKey = localFeedKeyByArticleKey[synced.articleKey] else {
                continue
            }
            synced.feedKey = feedKey
            didChange = true
        }
        return didChange
    }

    private func applySyncedArticleStatesToLocalArticles() -> Bool {
        let syncedStates = (try? modelContext.fetch(FetchDescriptor<SyncedArticleState>())) ?? []
        let allLocalArticles = (try? modelContext.fetch(FetchDescriptor<Article>())) ?? []
        var didChange = false

        for synced in syncedStates {
            let localArticles = allLocalArticles.filter { $0.articleKey == synced.articleKey }

            for article in localArticles {
                let localUpdatedAt = article.userStateUpdatedAt ?? .distantPast
                guard synced.updatedAt > localUpdatedAt else {
                    continue
                }

                let previousReactionValue = article.reactionValue
                let previousReactionCodes = article.reactionReasonCodes

                article.isRead = synced.isRead
                article.readAt = synced.readAt
                article.dismissedAt = synced.dismissedAt
                article.readingListAddedAt = synced.readingListAddedAt
                article.reactionValue = synced.reactionValue
                article.reactionReasonCodes = synced.reactionReasonCodes
                article.reactionUpdatedAt = synced.reactionUpdatedAt ?? (synced.reactionValue == nil ? nil : synced.updatedAt)

                if previousReactionValue != synced.reactionValue || previousReactionCodes != synced.reactionReasonCodes {
                    article.reactionUpdatedAt = synced.reactionUpdatedAt ?? (synced.reactionValue == nil ? nil : synced.updatedAt)
                }

                article.refreshQueryState()
                didChange = true
            }
        }

        return didChange
    }

    private func syncedPreferences() -> SyncedPreferences? {
        var descriptor = FetchDescriptor<SyncedPreferences>(
            predicate: #Predicate<SyncedPreferences> { $0.id == "standalone" }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func syncedFeedSubscription(feedKey: String) -> SyncedFeedSubscription? {
        var descriptor = FetchDescriptor<SyncedFeedSubscription>(
            predicate: #Predicate<SyncedFeedSubscription> { $0.feedKey == feedKey }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func syncedArticleState(articleKey: String) -> SyncedArticleState? {
        var descriptor = FetchDescriptor<SyncedArticleState>(
            predicate: #Predicate<SyncedArticleState> { $0.articleKey == articleKey }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertSyncedPreferences(from settings: AppSettings, updatedAt: Date) {
        let row = syncedPreferences() ?? {
            let newRow = SyncedPreferences()
            modelContext.insert(newRow)
            return newRow
        }()

        row.archiveAfterDays = settings.archiveAfterDays > 0 ? settings.archiveAfterDays : settings.retentionDays
        row.deleteArchivedAfterDays = settings.deleteArchivedAfterDays
        row.maxArticlesPerFeed = settings.maxArticlesPerFeed
        row.searchArchivedByDefault = settings.searchArchivedByDefault
        row.updatedAt = updatedAt
    }

    private func upsertSyncedArticleState(from article: Article, updatedAt: Date) {
        guard !article.articleKey.isEmpty else {
            return
        }

        let row = syncedArticleState(articleKey: article.articleKey) ?? {
            let newRow = SyncedArticleState(articleKey: article.articleKey)
            modelContext.insert(newRow)
            return newRow
        }()

        row.isRead = article.isRead
        row.readAt = article.readAt
        row.dismissedAt = article.dismissedAt
        row.readingListAddedAt = article.readingListAddedAt
        row.reactionValue = article.reactionValue
        row.reactionReasonCodes = article.reactionReasonCodes
        row.feedKey = article.feed?.feedKey ?? row.feedKey
        row.reactionUpdatedAt = article.reactionUpdatedAt
        row.updatedAt = updatedAt
    }
}
