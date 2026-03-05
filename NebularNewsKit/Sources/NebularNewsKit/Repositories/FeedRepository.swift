import Foundation
import SwiftData

// MARK: - Protocol

public protocol FeedRepositoryProtocol: Sendable {
    func list() async -> [Feed]
    func get(id: String) async -> Feed?
    func getByUrl(_ feedUrl: String) async -> Feed?
    func add(feedUrl: String, title: String) async throws -> Feed
    func delete(id: String) async throws
    func update(_ feed: Feed) async throws
    func setEnabled(id: String, enabled: Bool) async throws
    func recordPollSuccess(id: String, etag: String?, lastModified: String?, hadNewItems: Bool) async throws
    func recordPollError(id: String, message: String) async throws
}

// MARK: - Local Implementation

@ModelActor
public actor LocalFeedRepository: FeedRepositoryProtocol {

    public func list() async -> [Feed] {
        let descriptor = FetchDescriptor<Feed>(
            sortBy: [SortDescriptor(\.title, comparator: .localizedStandard)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    public func get(id: String) async -> Feed? {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func getByUrl(_ feedUrl: String) async -> Feed? {
        var descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.feedUrl == feedUrl }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    public func add(feedUrl: String, title: String) async throws -> Feed {
        // Check for duplicates
        if let existing = await getByUrl(feedUrl) {
            return existing
        }

        let feed = Feed(feedUrl: feedUrl, title: title)
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
        try modelContext.save()
    }

    public func setEnabled(id: String, enabled: Bool) async throws {
        guard let feed = await get(id: id) else { return }
        feed.isEnabled = enabled
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
}
