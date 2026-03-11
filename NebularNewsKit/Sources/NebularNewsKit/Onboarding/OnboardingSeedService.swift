import Foundation
import SwiftData

private let onboardingSelectedTopicAffinity = 0.6
private let onboardingAvoidedTopicAffinity = -0.6
private let onboardingSelectedFeedAffinity = 0.35

@ModelActor
actor LocalOnboardingSeedRepository {
    func applySeed(
        selectedInterests: [StarterInterest],
        avoidedInterests: [StarterInterest],
        selectedFeeds: [StarterFeedDefinition]
    ) throws -> OnboardingSeedResult {
        let normalizedSelectedFeeds = dedupedSelectedFeeds(selectedFeeds)
        let resolvedFeeds = try upsertSelectedFeeds(normalizedSelectedFeeds)
        try seedTopicAffinities(from: selectedInterests, targetAffinity: onboardingSelectedTopicAffinity)
        try seedTopicAffinities(from: avoidedInterests, targetAffinity: onboardingAvoidedTopicAffinity)
        try seedFeedAffinities(for: resolvedFeeds, targetAffinity: onboardingSelectedFeedAffinity)
        try modelContext.save()

        return OnboardingSeedResult(
            feedIDs: resolvedFeeds.map(\.id),
            selectedFeeds: normalizedSelectedFeeds
        )
    }

    private func dedupedSelectedFeeds(_ feeds: [StarterFeedDefinition]) -> [StarterFeedDefinition] {
        var byCanonicalURL: [String: StarterFeedDefinition] = [:]
        var orderedURLs: [String] = []

        for feed in feeds {
            guard let canonicalURL = canonicalStarterFeedURL(feed.feedURL) else { continue }
            if byCanonicalURL[canonicalURL] == nil {
                orderedURLs.append(canonicalURL)
            }
            byCanonicalURL[canonicalURL] = StarterFeedDefinition(
                id: feed.id,
                title: feed.title,
                feedURL: canonicalURL,
                aliases: feed.aliases
            )
        }

        return orderedURLs.compactMap { byCanonicalURL[$0] }
    }

    private func upsertSelectedFeeds(_ feeds: [StarterFeedDefinition]) throws -> [Feed] {
        let descriptor = FetchDescriptor<Feed>()
        let existingFeeds = (try? modelContext.fetch(descriptor)) ?? []
        var existingByCanonicalURL: [String: Feed] = [:]

        for feed in existingFeeds {
            guard let canonicalURL = canonicalStarterFeedURL(feed.feedUrl) else { continue }
            existingByCanonicalURL[canonicalURL] = feed
        }

        var resolvedFeeds: [Feed] = []

        for definition in feeds {
            guard let canonicalURL = canonicalStarterFeedURL(definition.feedURL) else { continue }

            if let existing = existingByCanonicalURL[canonicalURL] {
                if existing.title.isEmpty {
                    existing.title = definition.title
                }
                existing.isEnabled = true
                resolvedFeeds.append(existing)
                continue
            }

            let feed = Feed(feedUrl: canonicalURL, title: definition.title)
            feed.isEnabled = true
            modelContext.insert(feed)
            existingByCanonicalURL[canonicalURL] = feed
            resolvedFeeds.append(feed)
        }

        try modelContext.save()
        return resolvedFeeds
    }

    private func seedTopicAffinities(from interests: [StarterInterest], targetAffinity: Double) throws {
        guard !interests.isEmpty else { return }

        let tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        let tagsBySlug = Dictionary(uniqueKeysWithValues: tags.map { ($0.slug, $0) })
        let normalizedTagNames = Set(
            interests
                .flatMap(\.seedTagSlugs)
                .compactMap { tagsBySlug[$0]?.nameNormalized }
        )

        for normalizedName in normalizedTagNames {
            let row = try topicAffinityRow(for: normalizedName)
            row.affinity = targetAffinity > 0
                ? max(row.affinity, targetAffinity)
                : min(row.affinity, targetAffinity)
            row.interactionCount = max(row.interactionCount, 1)
            row.updatedAt = Date()
        }
    }

    private func seedFeedAffinities(for feeds: [Feed], targetAffinity: Double) throws {
        for feed in feeds {
            guard let feedKey = normalizedFeedKey(from: feed.feedUrl), !feedKey.isEmpty else { continue }
            let row = try feedAffinityRow(for: feedKey)
            row.affinity = max(row.affinity, targetAffinity)
            row.interactionCount = max(row.interactionCount, 1)
            row.updatedAt = Date()
        }
    }

    private func topicAffinityRow(for normalizedTagName: String) throws -> TopicAffinity {
        let descriptor = FetchDescriptor<TopicAffinity>(
            predicate: #Predicate<TopicAffinity> { $0.tagNameNormalized == normalizedTagName }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let row = TopicAffinity(tagNameNormalized: normalizedTagName, affinity: 0)
        modelContext.insert(row)
        return row
    }

    private func feedAffinityRow(for feedKey: String) throws -> FeedAffinity {
        let descriptor = FetchDescriptor<FeedAffinity>(
            predicate: #Predicate<FeedAffinity> { $0.feedKey == feedKey }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let row = FeedAffinity(feedKey: feedKey, affinity: 0)
        modelContext.insert(row)
        return row
    }
}

public actor OnboardingSeedService {
    private let modelContainer: ModelContainer
    private let keychainService: String
    private let repository: LocalOnboardingSeedRepository

    public init(
        modelContainer: ModelContainer,
        keychainService: String = "com.nebularnews.ios"
    ) {
        self.modelContainer = modelContainer
        self.keychainService = keychainService
        self.repository = LocalOnboardingSeedRepository(modelContainer: modelContainer)
    }

    public func apply(request: OnboardingSeedRequest) async throws -> OnboardingSeedResult {
        let personalization = LocalStandalonePersonalizationService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )
        await personalization.bootstrap()

        let interestsByID = Dictionary(uniqueKeysWithValues: starterInterestCatalog.map { ($0.id, $0) })
        let selectedInterests = request.selectedInterestIDs.compactMap { interestsByID[$0] }
        let avoidedInterests = request.avoidedInterestIDs.compactMap { interestsByID[$0] }

        return try await repository.applySeed(
            selectedInterests: selectedInterests,
            avoidedInterests: avoidedInterests,
            selectedFeeds: request.selectedFeeds
        )
    }
}
