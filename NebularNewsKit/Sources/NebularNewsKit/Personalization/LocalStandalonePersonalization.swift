import Foundation
import SwiftData

private let targetedReasonSignalMultiplier = 1.5
private let backgroundReasonSignalMultiplier = 0.25
private let explicitAffinityMultiplier = 1.5
private let implicitAffinityMultiplier = 1.0
private let impactedArticleRescoreLimit = 100

public struct PersonalizationTagSnapshot: Sendable, Hashable {
    public let id: String
    public let name: String
    public let normalizedName: String
}

struct PersonalizationArticleContext: Sendable {
    let id: String
    let canonicalURL: String?
    let title: String?
    let authorNormalized: String?
    let publishedAt: Date?
    let feedID: String?
    let feedTitle: String?
    let siteHostname: String?
    let contentText: String?
    let tags: [PersonalizationTagSnapshot]
}

fileprivate struct StoredArticlePersonalizationSnapshot: Sendable {
    let context: PersonalizationArticleContext
    let personalizationVersion: Int
    let systemTagIDs: [String]
    let signalScores: [StoredSignalScore]
    let score: Int?
    let scoreStatus: LocalScoreStatus?
    let weightedAverage: Double?
    let confidence: Double?
    let preferenceConfidence: Double?
}

public struct PersonalizationDebugSnapshot: Sendable, Hashable {
    public let articleID: String
    public let personalizationVersion: Int
    public let matchedSourceProfiles: [String]
    public let currentTags: [PersonalizationTagSnapshot]
    public let systemTagIDs: [String]
    public let tagDecisions: [DeterministicTagDecision]
    public let signalScores: [StoredSignalScore]
    public let weights: [LocalSignalWeight]
    public let score: Int?
    public let scoreStatus: LocalScoreStatus?
    public let weightedAverage: Double?
    public let confidence: Double?
    public let preferenceConfidence: Double?
}

#if DEBUG
public struct TrackedTechCoverageSnapshot: Sendable, Hashable {
    public let familyName: String
    public let total: Int
    public let currentVersion: Int
    public let systemTagged: Int
    public let reacted: Int
    public let reactedTagged: Int
}
#endif

public struct FeedReputation: Sendable, Hashable {
    public let feedbackCount: Int
    public let weightedFeedbackCount: Double
    public let ratingSum: Double
    public let score: Double

    public init(feedbackCount: Int, weightedFeedbackCount: Double, ratingSum: Double, score: Double) {
        self.feedbackCount = feedbackCount
        self.weightedFeedbackCount = weightedFeedbackCount
        self.ratingSum = ratingSum
        self.score = score
    }
}

@ModelActor
actor LocalPersonalizationRepository {
    func bootstrapStarterData() async throws {
        try ensureStarterCanonicalTags()
        try ensureDefaultSignalWeights()
    }

    func listStaleArticleIDs(limit: Int = 25, trackedTechOnly: Bool = false) async -> [String] {
        let staleVersion = currentPersonalizationVersion
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.personalizationVersion < staleVersion },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )

        guard let articles = try? modelContext.fetch(descriptor) else {
            return []
        }

        var reactedTrackedTechArticleIDs: [String] = []
        var trackedTechArticleIDs: [String] = []
        var otherArticleIDs: [String] = []

        for article in articles {
            let context = makeArticleContext(from: article)
            let isTrackedTech = primaryTrackedTechFeedFamily(
                feedTitle: context.feedTitle,
                siteHostname: context.siteHostname
            ) != nil

            if isTrackedTech {
                if article.reactionValue != nil {
                    reactedTrackedTechArticleIDs.append(article.id)
                } else {
                    trackedTechArticleIDs.append(article.id)
                }
            } else if !trackedTechOnly {
                otherArticleIDs.append(article.id)
            }
        }

        return Array((reactedTrackedTechArticleIDs + trackedTechArticleIDs + otherArticleIDs).prefix(limit))
    }

    fileprivate func storedArticleSnapshot(for articleID: String) async -> StoredArticlePersonalizationSnapshot? {
        guard let article = try? fetchArticle(articleID) else {
            return nil
        }

        return StoredArticlePersonalizationSnapshot(
            context: makeArticleContext(from: article),
            personalizationVersion: article.personalizationVersion,
            systemTagIDs: article.systemTagIds,
            signalScores: article.signalScores,
            score: article.score,
            scoreStatus: article.scoreStatusValue,
            weightedAverage: article.scoreWeightedAverage,
            confidence: article.scoreConfidence,
            preferenceConfidence: article.scorePreferenceConfidence
        )
    }

    func needsRetagging(articleID: String) async -> Bool {
        guard let article = try? fetchArticle(articleID) else { return false }
        return article.personalizationVersion < currentPersonalizationVersion || (article.tags?.isEmpty ?? true)
    }

#if DEBUG
    func trackedTechCoverageSnapshot() async -> [TrackedTechCoverageSnapshot] {
        struct Counts {
            var total = 0
            var currentVersion = 0
            var systemTagged = 0
            var reacted = 0
            var reactedTagged = 0
        }

        let descriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        var countsByFamilyName = Dictionary(uniqueKeysWithValues: trackedTechFeedFamilies.map { ($0.name, Counts()) })

        for article in articles {
            let context = makeArticleContext(from: article)
            guard let family = primaryTrackedTechFeedFamily(
                feedTitle: context.feedTitle,
                siteHostname: context.siteHostname
            ) else {
                continue
            }

            var counts = countsByFamilyName[family.name] ?? Counts()
            counts.total += 1
            if article.personalizationVersion == currentPersonalizationVersion {
                counts.currentVersion += 1
            }
            if !article.systemTagIds.isEmpty {
                counts.systemTagged += 1
            }
            if article.reactionValue != nil {
                counts.reacted += 1
                if !article.systemTagIds.isEmpty {
                    counts.reactedTagged += 1
                }
            }
            countsByFamilyName[family.name] = counts
        }

        return trackedTechFeedFamilies.map { family in
            let counts = countsByFamilyName[family.name] ?? Counts()
            return TrackedTechCoverageSnapshot(
                familyName: family.name,
                total: counts.total,
                currentVersion: counts.currentVersion,
                systemTagged: counts.systemTagged,
                reacted: counts.reacted,
                reactedTagged: counts.reactedTagged
            )
        }
    }
#endif

    func impactedArticleIDs(for articleID: String, limit: Int) async -> [String] {
        guard let article = try? fetchArticle(articleID) else { return [] }

        let feedID = article.feed?.id
        let authorNormalized = normalizeAuthor(article.author)
        let tagIDs = Set((article.tags ?? []).map(\.id))
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []

        var impactedIDs: [String] = []
        var seen: Set<String> = []

        for candidate in articles {
            guard candidate.id != article.id else { continue }

            let matchesFeed = feedID != nil && candidate.feed?.id == feedID
            let matchesAuthor = authorNormalized != nil && normalizeAuthor(candidate.author) == authorNormalized
            let candidateTagIDs = Set((candidate.tags ?? []).map(\.id))
            let matchesTags = !tagIDs.isEmpty && !candidateTagIDs.isDisjoint(with: tagIDs)

            guard matchesFeed || matchesAuthor || matchesTags else { continue }
            guard seen.insert(candidate.id).inserted else { continue }

            impactedIDs.append(candidate.id)
            if impactedIDs.count == limit {
                break
            }
        }

        return impactedIDs
    }

    func listCanonicalTagCandidates() async -> [DeterministicTagCandidate] {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.isCanonical == true },
            sortBy: [SortDescriptor(\.name, comparator: .localizedStandard)]
        )

        guard let tags = try? modelContext.fetch(descriptor) else {
            return []
        }

        return tags.map {
            DeterministicTagCandidate(
                id: $0.id,
                name: $0.name,
                normalizedName: $0.nameNormalized,
                slug: $0.slug,
                articleCount: $0.articles?.count ?? 0
            )
        }
    }

    func feedTagPriors(feedID: String?, excluding articleID: String) async -> [String: FeedTagPrior] {
        guard let feedID,
              let feed = try? fetchFeed(feedID)
        else {
            return [:]
        }

        let feedArticles = (feed.articles ?? []).filter { $0.id != articleID }
        let taggedArticles = feedArticles.filter { !($0.tags?.isEmpty ?? true) }
        guard !taggedArticles.isEmpty else {
            return [:]
        }

        let totalTaggedArticles = taggedArticles.count
        var countsByTagID: [String: Int] = [:]

        for article in taggedArticles {
            let uniqueTagIDs = Set((article.tags ?? []).map(\.id))
            for tagID in uniqueTagIDs {
                countsByTagID[tagID, default: 0] += 1
            }
        }

        return countsByTagID.mapValues { count in
            FeedTagPrior(
                taggedArticleCount: count,
                ratio: Double(count) / Double(totalTaggedArticles)
            )
        }
    }

    func applySystemTags(articleID: String, desiredTagIDs: [String]) async throws {
        let article = try fetchArticle(articleID)
        let currentSystemTagIDs = Set(article.systemTagIds)
        var currentTags = article.tags ?? []
        let currentTagIDs = Set(currentTags.map(\.id))

        let removableSystemTagIDs = currentSystemTagIDs.subtracting(desiredTagIDs)
        if !removableSystemTagIDs.isEmpty {
            currentTags.removeAll { removableSystemTagIDs.contains($0.id) }
        }

        var persistedSystemTagIDs: [String] = []
        let desiredSet = Set(desiredTagIDs)

        for tagID in desiredTagIDs {
            if currentTagIDs.contains(tagID) && !currentSystemTagIDs.contains(tagID) {
                continue
            }

            if let tag = try? fetchTag(tagID), !currentTags.contains(where: { $0.id == tagID }) {
                currentTags.append(tag)
            }

            if desiredSet.contains(tagID) {
                persistedSystemTagIDs.append(tagID)
            }
        }

        article.tags = currentTags
        article.systemTagIdsJson = encodeJSON(persistedSystemTagIDs)
        try modelContext.save()
    }

    func loadSignalWeights() async -> [LocalSignalWeight] {
        let descriptor = FetchDescriptor<SignalWeight>(
            sortBy: [SortDescriptor(\.signalName, comparator: .localizedStandard)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let bySignalName = Dictionary(uniqueKeysWithValues: rows.map { ($0.signalName, $0) })

        return SignalName.allCases.map { signal in
            let existing = bySignalName[signal.rawValue]
            return LocalSignalWeight(
                signal: signal,
                weight: existing?.weight ?? defaultSignalWeights[signal] ?? 1.0,
                sampleCount: existing?.sampleCount ?? 0
            )
        }
    }

    func feedReputation(feedID: String?) async -> FeedReputation {
        guard let feedID,
              let feed = try? fetchFeed(feedID)
        else {
            return FeedReputation(feedbackCount: 0, weightedFeedbackCount: 0, ratingSum: 0, score: 0)
        }

        var feedbackCount = 0
        var weightedFeedbackCount = 0.0
        var ratingSum = 0.0

        for article in feed.articles ?? [] {
            guard let reactionValue = article.reactionValue else { continue }
            feedbackCount += 1
            let reasonCodes = article.reactionReasonCodes?
                .split(separator: ",")
                .map(String.init) ?? []
            let voteWeight = hasSourceReason(reasonCodes) ? sourceReputationVoteWeight : 1.0
            weightedFeedbackCount += voteWeight
            ratingSum += Double(reactionValue) * voteWeight
        }

        let score = feedbackCount > 0 ? (ratingSum / (weightedFeedbackCount + sourceReputationPriorWeight)) : 0
        return FeedReputation(
            feedbackCount: feedbackCount,
            weightedFeedbackCount: weightedFeedbackCount,
            ratingSum: ratingSum,
            score: score
        )
    }

    func topicAffinityMap(for normalizedTagNames: [String]) async -> [String: TopicAffinity] {
        guard !normalizedTagNames.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<TopicAffinity>()
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let allowed = Set(normalizedTagNames)
        return rows.reduce(into: [:]) { partial, row in
            if allowed.contains(row.tagNameNormalized) {
                partial[row.tagNameNormalized] = row
            }
        }
    }

    func authorAffinity(for authorNormalized: String?) async -> AuthorAffinity? {
        guard let authorNormalized, !authorNormalized.isEmpty else { return nil }
        let descriptor = FetchDescriptor<AuthorAffinity>(
            predicate: #Predicate<AuthorAffinity> { $0.authorNormalized == authorNormalized }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func persistScore(articleID: String, algorithmicScore: AlgorithmicScore) async throws {
        let article = try fetchArticle(articleID)
        let confidencePercent = Int((algorithmicScore.confidence * 100).rounded())
        let signalSummary = algorithmicScore.signals
            .map { signal in
                "• \(signal.signal.rawValue): \(formatDecimal(signal.normalizedValue)) (raw: \(formatDecimal(signal.rawValue)))"
            }
            .joined(separator: "\n")
        let explanation = """
        Algorithmic (\(confidencePercent)% confidence)
        Weighted average: \(formatDecimal(algorithmicScore.weightedAverage))
        \(signalSummary.isEmpty ? "" : "\n\(signalSummary)")
        """

        article.score = algorithmicScore.status == .ready ? algorithmicScore.score : nil
        article.scoreLabel = algorithmicScore.status == .ready
            ? "Algorithmic (\(confidencePercent)% confidence)"
            : "Learning your preferences"
        article.scoreConfidence = algorithmicScore.confidence
        article.scorePreferenceConfidence = algorithmicScore.preferenceConfidence
        article.scoreWeightedAverage = algorithmicScore.weightedAverage
        article.scoreStatus = algorithmicScore.status.rawValue
        article.signalScoresJson = encodeJSON(algorithmicScore.signals)
        article.scoreExplanation = algorithmicScore.status == .ready ? explanation : nil
        article.personalizationVersion = currentPersonalizationVersion
        try modelContext.save()
    }

    func updateWeightsFromReaction(
        direction: Int,
        signalScores: [StoredSignalScore],
        reasonCodes: [ArticleReactionReasonCode]
    ) async throws {
        let targetSignals = targetSignals(for: reasonCodes)
        let useReasonTargeting = !targetSignals.isEmpty

        for signalScore in signalScores {
            let row = try signalWeightRow(for: signalScore.signal)
            let alpha = effectiveAlpha(learningRate: scoringLearningRate, sampleCount: row.sampleCount)
            let error = direction == 1 ? signalScore.normalizedValue : -signalScore.normalizedValue
            let multiplier = useReasonTargeting
                ? (targetSignals.contains(signalScore.signal) ? targetedReasonSignalMultiplier : backgroundReasonSignalMultiplier)
                : 1.0
            row.weight = max(0.01, row.weight + (alpha * error * multiplier))
            row.sampleCount += 1
            row.updatedAt = Date()
        }

        try modelContext.save()
    }

    func updateTopicAffinities(
        for normalizedTagNames: [String],
        direction: Int,
        multiplier: Double
    ) async throws {
        for normalizedTagName in Set(normalizedTagNames) {
            let row = try topicAffinityRow(for: normalizedTagName)
            let alpha = effectiveAlpha(learningRate: scoringLearningRate, sampleCount: row.interactionCount)
            row.affinity += alpha * Double(direction) * multiplier
            row.interactionCount += 1
            row.updatedAt = Date()
        }
        try modelContext.save()
    }

    func updateAuthorAffinity(
        for authorNormalized: String,
        direction: Int,
        multiplier: Double
    ) async throws {
        let row = try authorAffinityRow(for: authorNormalized)
        let alpha = effectiveAlpha(learningRate: scoringLearningRate, sampleCount: row.interactionCount)
        row.affinity += alpha * Double(direction) * multiplier
        row.interactionCount += 1
        row.updatedAt = Date()
        try modelContext.save()
    }

    private func ensureStarterCanonicalTags() throws {
        let descriptor = FetchDescriptor<Tag>()
        let existingTags = (try? modelContext.fetch(descriptor)) ?? []
        let tagsByNormalizedName = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.nameNormalized, $0) })

        for starter in starterCanonicalTags {
            let normalizedName = Tag.normalizeName(starter.name)
            if let existing = tagsByNormalizedName[normalizedName] {
                existing.slug = starter.slug
                existing.isCanonical = true
                continue
            }

            let tag = Tag(
                id: starter.id,
                name: starter.name,
                slug: starter.slug,
                isCanonical: true
            )
            modelContext.insert(tag)
        }

        try modelContext.save()
    }

    private func ensureDefaultSignalWeights() throws {
        let descriptor = FetchDescriptor<SignalWeight>()
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let rowsBySignalName = Dictionary(uniqueKeysWithValues: rows.map { ($0.signalName, $0) })

        for signal in SignalName.allCases {
            if let existing = rowsBySignalName[signal.rawValue] {
                if existing.weight <= 0 {
                    existing.weight = defaultSignalWeights[signal] ?? 1.0
                }
                continue
            }

            modelContext.insert(
                SignalWeight(
                    signalName: signal.rawValue,
                    weight: defaultSignalWeights[signal] ?? 1.0
                )
            )
        }

        try modelContext.save()
    }

    private func signalWeightRow(for signal: SignalName) throws -> SignalWeight {
        let descriptor = FetchDescriptor<SignalWeight>(
            predicate: #Predicate<SignalWeight> { $0.signalName == signal.rawValue }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let row = SignalWeight(signalName: signal.rawValue, weight: defaultSignalWeights[signal] ?? 1.0)
        modelContext.insert(row)
        return row
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

    private func authorAffinityRow(for normalizedAuthor: String) throws -> AuthorAffinity {
        let descriptor = FetchDescriptor<AuthorAffinity>(
            predicate: #Predicate<AuthorAffinity> { $0.authorNormalized == normalizedAuthor }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let row = AuthorAffinity(authorNormalized: normalizedAuthor, affinity: 0)
        modelContext.insert(row)
        return row
    }

    private func fetchArticle(_ articleID: String) throws -> Article {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == articleID }
        )
        guard let article = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "LocalPersonalizationRepository", code: 404)
        }
        return article
    }

    private func fetchFeed(_ feedID: String) throws -> Feed {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate<Feed> { $0.id == feedID }
        )
        guard let feed = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "LocalPersonalizationRepository", code: 404)
        }
        return feed
    }

    private func fetchTag(_ tagID: String) throws -> Tag {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.id == tagID }
        )
        guard let tag = try modelContext.fetch(descriptor).first else {
            throw NSError(domain: "LocalPersonalizationRepository", code: 404)
        }
        return tag
    }

    private func makeArticleContext(from article: Article) -> PersonalizationArticleContext {
        let contentText = [
            article.contentHtml?.strippedHTML,
            article.excerpt?.strippedHTML
        ]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
        .first

        let tags = (article.tags ?? []).map {
            PersonalizationTagSnapshot(id: $0.id, name: $0.name, normalizedName: $0.nameNormalized)
        }

        return PersonalizationArticleContext(
            id: article.id,
            canonicalURL: article.canonicalUrl,
            title: article.title,
            authorNormalized: normalizeAuthor(article.author),
            publishedAt: article.publishedAt,
            feedID: article.feed?.id,
            feedTitle: article.feed?.title,
            siteHostname: article.feed?.siteUrl.flatMap(hostname(from:)) ?? article.canonicalUrl.flatMap(hostname(from:)),
            contentText: contentText,
            tags: tags
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public actor LocalStandalonePersonalizationService {
    private let repository: LocalPersonalizationRepository

    public init(modelContainer: ModelContainer) {
        self.repository = LocalPersonalizationRepository(modelContainer: modelContainer)
    }

    public func bootstrap() async {
        try? await repository.bootstrapStarterData()
    }

    @discardableResult
    public func processPendingArticles(limit: Int = 25) async -> Int {
        await bootstrap()
        let articleIDs = await repository.listStaleArticleIDs(limit: limit)
        for articleID in articleIDs {
            try? await retagAndScoreArticle(articleID: articleID)
        }
        return articleIDs.count
    }

#if DEBUG
    @discardableResult
    public func reprocessAllStaleArticles(batchSize: Int = 200) async -> Int {
        await bootstrap()
        var totalProcessed = 0

        while true {
            let processed = await processPendingArticles(limit: batchSize)
            totalProcessed += processed

            if processed < batchSize {
                break
            }
        }

        return totalProcessed
    }

    @discardableResult
    public func reprocessTrackedTechFeeds(batchSize: Int = 200) async -> Int {
        await bootstrap()
        var totalProcessed = 0

        while true {
            let articleIDs = await repository.listStaleArticleIDs(limit: batchSize, trackedTechOnly: true)
            totalProcessed += articleIDs.count

            for articleID in articleIDs {
                try? await retagAndScoreArticle(articleID: articleID)
            }

            if articleIDs.count < batchSize {
                break
            }
        }

        return totalProcessed
    }

    public func trackedTechCoverageSnapshot() async -> [TrackedTechCoverageSnapshot] {
        await bootstrap()
        return await repository.trackedTechCoverageSnapshot()
    }
#endif

    public func debugSnapshot(articleID: String) async -> PersonalizationDebugSnapshot? {
        await bootstrap()
        guard let stored = await repository.storedArticleSnapshot(for: articleID) else { return nil }

        let evaluation = await deterministicTagEvaluation(for: stored.context)
        let weights = await repository.loadSignalWeights()

        return PersonalizationDebugSnapshot(
            articleID: articleID,
            personalizationVersion: stored.personalizationVersion,
            matchedSourceProfiles: evaluation.matchedSourceProfiles,
            currentTags: stored.context.tags.sorted { $0.name < $1.name },
            systemTagIDs: stored.systemTagIDs.sorted(),
            tagDecisions: evaluation.decisions,
            signalScores: stored.signalScores,
            weights: weights,
            score: stored.score,
            scoreStatus: stored.scoreStatus,
            weightedAverage: stored.weightedAverage,
            confidence: stored.confidence,
            preferenceConfidence: stored.preferenceConfidence
        )
    }

    public func retagAndScoreArticle(articleID: String) async throws {
        await bootstrap()
        guard let snapshot = await repository.storedArticleSnapshot(for: articleID) else { return }

        let evaluation = await deterministicTagEvaluation(for: snapshot.context)
        try await repository.applySystemTags(articleID: articleID, desiredTagIDs: evaluation.decisions.map(\.tagId))
        try await rescoreArticle(articleID: articleID)
    }

    public func rescoreArticle(articleID: String) async throws {
        await bootstrap()
        guard let snapshot = await repository.storedArticleSnapshot(for: articleID) else { return }
        let context = snapshot.context

        let topicAffinityMap = await repository.topicAffinityMap(for: context.tags.map(\.normalizedName))
        let authorAffinity = await repository.authorAffinity(for: context.authorNormalized)
        let feedReputation = await repository.feedReputation(feedID: context.feedID)
        let signalScores = extractSignals(
            context: context,
            topicAffinities: topicAffinityMap,
            authorAffinity: authorAffinity,
            feedReputation: feedReputation
        )
        let weights = await repository.loadSignalWeights()
        let score = computeAlgorithmicScore(signals: signalScores, weights: weights)
        try await repository.persistScore(articleID: articleID, algorithmicScore: score)
    }

    public func processReactionChange(
        articleID: String,
        previousValue: Int?,
        newValue: Int?,
        reasonCodes: [ArticleReactionReasonCode]
    ) async {
        await bootstrap()
        guard shouldLearnFromReactionChange(previousValue: previousValue, newValue: newValue),
              let finalValue = newValue
        else {
            return
        }

        guard await refreshSnapshot(articleID: articleID) != nil else {
            return
        }

        // Recompute once after the user's reaction is stored so source reputation
        // can participate in the learning update on the same turn.
        try? await rescoreArticle(articleID: articleID)

        guard let snapshot = await repository.storedArticleSnapshot(for: articleID) else {
            return
        }

        let context = snapshot.context
        let signalScores = snapshot.signalScores
        guard !signalScores.isEmpty else { return }

        try? await repository.updateWeightsFromReaction(
            direction: finalValue,
            signalScores: signalScores,
            reasonCodes: reasonCodes
        )

        if reasonCodes.isEmpty || hasTopicReason(reasonCodes) {
            let multiplier = hasTopicReason(reasonCodes) ? explicitAffinityMultiplier : implicitAffinityMultiplier
            try? await repository.updateTopicAffinities(
                for: context.tags.map(\.normalizedName),
                direction: finalValue,
                multiplier: multiplier
            )
        }

        if (reasonCodes.isEmpty || hasAuthorReason(reasonCodes)),
           let authorNormalized = context.authorNormalized,
           !authorNormalized.isEmpty {
            let multiplier = hasAuthorReason(reasonCodes) ? explicitAffinityMultiplier : implicitAffinityMultiplier
            try? await repository.updateAuthorAffinity(
                for: authorNormalized,
                direction: finalValue,
                multiplier: multiplier
            )
        }

        try? await rescoreArticle(articleID: articleID)
        await rescoreRelatedArticles(for: articleID)
    }

    private func refreshSnapshot(articleID: String) async -> StoredArticlePersonalizationSnapshot? {
        let needsRetagging = await repository.needsRetagging(articleID: articleID)
        if needsRetagging {
            try? await retagAndScoreArticle(articleID: articleID)
        }

        guard var snapshot = await repository.storedArticleSnapshot(for: articleID) else {
            return nil
        }

        if snapshot.signalScores.isEmpty {
            try? await rescoreArticle(articleID: articleID)
            if let refreshedSnapshot = await repository.storedArticleSnapshot(for: articleID) {
                snapshot = refreshedSnapshot
            }
        }

        return snapshot
    }

    private func rescoreRelatedArticles(for articleID: String) async {
        let impactedIDs = await repository.impactedArticleIDs(for: articleID, limit: impactedArticleRescoreLimit)

        for impactedID in impactedIDs {
            if await repository.needsRetagging(articleID: impactedID) {
                try? await retagAndScoreArticle(articleID: impactedID)
            } else {
                try? await rescoreArticle(articleID: impactedID)
            }
        }
    }

    private func deterministicTagEvaluation(for context: PersonalizationArticleContext) async -> DeterministicTagEvaluation {
        let candidates = await repository.listCanonicalTagCandidates()
        let priors = await repository.feedTagPriors(feedID: context.feedID, excluding: context.id)

        return generateDeterministicTagEvaluation(
            candidates: candidates,
            context: DeterministicTaggingContext(
                title: context.title,
                canonicalURL: context.canonicalURL,
                contentText: context.contentText,
                feedTitle: context.feedTitle,
                siteHostname: context.siteHostname
            ),
            feedPriorsByTagId: priors
        )
    }

    private func extractSignals(
        context: PersonalizationArticleContext,
        topicAffinities: [String: TopicAffinity],
        authorAffinity: AuthorAffinity?,
        feedReputation: FeedReputation
    ) -> [StoredSignalScore] {
        var signals: [StoredSignalScore] = []

        if !context.tags.isEmpty {
            let matched = context.tags.compactMap { topicAffinities[$0.normalizedName]?.affinity }
            if !matched.isEmpty {
                let average = matched.reduce(0, +) / Double(matched.count)
                signals.append(
                    StoredSignalScore(
                        signal: .topicAffinity,
                        rawValue: average,
                        normalizedValue: sigmoid(average, steepness: 2),
                        isDataBacked: true
                    )
                )
            }
        }

        if feedReputation.feedbackCount > 0 {
            signals.append(
                StoredSignalScore(
                    signal: .sourceReputation,
                    rawValue: feedReputation.score,
                    normalizedValue: clamped((feedReputation.score + 1) / 2),
                    isDataBacked: true
                )
            )
        }

        if let publishedAt = context.publishedAt {
            let ageHours = max(0, Date().timeIntervalSince(publishedAt) / 3600)
            signals.append(
                StoredSignalScore(
                    signal: .contentFreshness,
                    rawValue: ageHours,
                    normalizedValue: exponentialDecay(elapsed: ageHours, halfLife: 168),
                    isDataBacked: true
                )
            )
        }

        if let contentText = context.contentText, !contentText.isEmpty {
            let wordCount = Double(contentText.split(whereSeparator: \.isWhitespace).count)
            signals.append(
                StoredSignalScore(
                    signal: .contentDepth,
                    rawValue: wordCount,
                    normalizedValue: logisticRamp(value: wordCount, min: 200, max: 2000),
                    isDataBacked: true
                )
            )
        }

        if let authorAffinity {
            signals.append(
                StoredSignalScore(
                    signal: .authorAffinity,
                    rawValue: authorAffinity.affinity,
                    normalizedValue: sigmoid(authorAffinity.affinity, steepness: 2),
                    isDataBacked: true
                )
            )
        }

        if !context.tags.isEmpty {
            var signedMatchSum = 0.0
            var knownAffinities = 0

            for tag in context.tags {
                guard let affinity = topicAffinities[tag.normalizedName]?.affinity, affinity != 0 else {
                    continue
                }
                knownAffinities += 1
                signedMatchSum += affinity > 0 ? 1 : -1
            }

            if knownAffinities > 0 {
                let ratio = signedMatchSum / Double(context.tags.count)
                signals.append(
                    StoredSignalScore(
                        signal: .tagMatchRatio,
                        rawValue: ratio,
                        normalizedValue: clamped((ratio + 1) / 2),
                        isDataBacked: true
                    )
                )
            }
        }

        return signals
    }
}

private func hostname(from value: String) -> String? {
    guard let url = URL(string: value), let host = url.host else { return nil }
    return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
}

private func normalizeAuthor(_ value: String?) -> String? {
    guard let value else { return nil }

    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    return normalized.isEmpty ? nil : normalized
}

private func sigmoid(_ value: Double, steepness: Double) -> Double {
    1 / (1 + Foundation.exp(-steepness * value))
}

private func exponentialDecay(elapsed: Double, halfLife: Double) -> Double {
    Foundation.exp((-elapsed * Foundation.log(2)) / halfLife)
}

private func logisticRamp(value: Double, min: Double, max: Double) -> Double {
    if value <= min { return 0 }
    if value >= max { return 1 }
    return (value - min) / (max - min)
}

private func effectiveAlpha(learningRate: Double, sampleCount: Int) -> Double {
    learningRate / (1 + (Double(sampleCount) / scoringDampingFactor))
}

private func clamped(_ value: Double) -> Double {
    max(0, min(1, value))
}

private func formatDecimal(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    formatter.minimumIntegerDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f", value)
}
