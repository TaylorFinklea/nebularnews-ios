import Foundation
import SwiftData

// MARK: - Protocol

public protocol FeedRepositoryProtocol: Sendable {
    func list() async -> [Feed]
    func listSnapshots() async -> [FeedSnapshot]
    func get(id: String) async -> Feed?
    func getByUrl(_ feedUrl: String) async -> Feed?
    func add(feedUrl: String, title: String) async throws -> Feed
    func delete(id: String) async throws
    func update(_ feed: Feed) async throws
    func setEnabled(id: String, enabled: Bool) async throws
    func updateMetadata(id: String, title: String?, siteUrl: String?, iconUrl: String?) async throws
    func recordPollSuccess(id: String, etag: String?, lastModified: String?, hadNewItems: Bool) async throws
    func recordPollError(id: String, message: String) async throws
}

// MARK: - Local Implementation

@ModelActor
public actor LocalFeedRepository: FeedRepositoryProtocol {
    public func list() async -> [Feed] {
        ensureCanonicalStoredFeedURLs()
        let descriptor = FetchDescriptor<Feed>(
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    public func listSnapshots() async -> [FeedSnapshot] {
        ensureCanonicalStoredFeedURLs()
        let descriptor = FetchDescriptor<Feed>(
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        let feeds = (try? modelContext.fetch(descriptor)) ?? []
        return feeds.map { feed in
            FeedSnapshot(
                id: feed.id,
                feedUrl: feed.feedUrl,
                title: feed.title,
                etag: feed.etag,
                lastModified: feed.lastModified,
                isEnabled: feed.isEnabled,
                consecutiveErrors: feed.consecutiveErrors,
                lastPolledAt: feed.lastPolledAt
            )
        }
    }

    public func get(id: String) async -> Feed? {
        ensureCanonicalStoredFeedURLs()
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func getByUrl(_ feedUrl: String) async -> Feed? {
        ensureCanonicalStoredFeedURLs()
        let normalizedURL = canonicalFeedURLForStorage(feedUrl) ?? feedUrl
        let feedKey = normalizedFeedKey(from: normalizedURL) ?? normalizedURL
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.feedKey == feedKey }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func add(feedUrl: String, title: String) async throws -> Feed {
        ensureCanonicalStoredFeedURLs()
        let normalizedURL = canonicalFeedURLForStorage(feedUrl) ?? feedUrl

        // Check for duplicates
        if let existing = await getByUrl(normalizedURL) {
            return existing
        }

        let feed = Feed(feedUrl: normalizedURL, title: title)
        modelContext.insert(feed)
        try modelContext.save()
        return feed
    }

    public func delete(id: String) async throws {
        guard let feed = await get(id: id) else { return }
        modelContext.delete(feed)
        try modelContext.save()
    }

    public func update(_ feed: Feed) async throws {
        feed.refreshIdentity()
        try modelContext.save()
    }

    public func setEnabled(id: String, enabled: Bool) async throws {
        guard let feed = await get(id: id) else { return }
        feed.isEnabled = enabled
        try modelContext.save()
    }

    public func updateMetadata(id: String, title: String?, siteUrl: String?, iconUrl: String?) async throws {
        guard let feed = await get(id: id) else { return }
        // Only update title if it's currently empty (user-set titles take precedence)
        if let title, feed.title.isEmpty {
            feed.title = title
        }
        if let siteUrl { feed.siteUrl = siteUrl }
        if let iconUrl { feed.iconUrl = iconUrl }
        try modelContext.save()
    }

    public func recordPollSuccess(
        id: String,
        etag: String?,
        lastModified: String?,
        hadNewItems: Bool
    ) async throws {
        guard let feed = await get(id: id) else { return }
        feed.lastPolledAt = Date()
        feed.etag = etag ?? feed.etag
        feed.lastModified = lastModified ?? feed.lastModified
        feed.errorMessage = nil
        feed.consecutiveErrors = 0
        if hadNewItems {
            feed.lastNewItemAt = Date()
        }
        try modelContext.save()
    }

    public func recordPollError(id: String, message: String) async throws {
        guard let feed = await get(id: id) else { return }
        feed.lastPolledAt = Date()
        feed.errorMessage = message
        feed.consecutiveErrors += 1
        try modelContext.save()
    }

    private func ensureCanonicalStoredFeedURLs() {
        let feeds = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        var didChange = false

        for feed in feeds {
            let previousURL = feed.feedUrl
            let previousKey = feed.feedKey
            feed.refreshIdentity()
            if previousURL != feed.feedUrl || previousKey != feed.feedKey {
                didChange = true
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }
}
