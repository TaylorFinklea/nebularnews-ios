import Foundation
import SwiftData

private let targetedReasonSignalMultiplier = 1.5
private let backgroundReasonSignalMultiplier = 0.25
private let explicitAffinityMultiplier = 1.5
private let implicitAffinityMultiplier = 1.0
private let dismissAffinityMultiplier = 0.35
private let impactedArticleRescoreLimit = 100
private let tagSuggestionCandidateScanLimit = 400
private let tagSuggestionCandidateLimit = 24
private let maxGeneratedTagSuggestions = 2
private let strongSuggestionConfidenceFloor = 0.88
private let minimumAttachedTagsForSuggestionSkip = 3

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
    let feedKey: String?
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

fileprivate enum HistoricalLearningEventKind: Sendable {
    case reaction
    case dismiss
}

fileprivate struct HistoricalLearningEvent: Sendable {
    let articleID: String
    let kind: HistoricalLearningEventKind
    let timestamp: Date
    let reactionValue: Int?
    let reasonCodes: [ArticleReactionReasonCode]
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
public struct PersonalizationScoreHistogramEntry: Sendable, Hashable {
    public let score: Int
    public let count: Int
}

public struct PersonalizationAuditSnapshot: Sendable, Hashable {
    public let totalArticles: Int
    public let currentVersionArticles: Int
    public let staleArticles: Int
    public let totalReadyScores: Int
    public let readyScoreHistogram: [PersonalizationScoreHistogramEntry]
    public let recentReadyScores: Int
    public let recentReadyScoreHistogram: [PersonalizationScoreHistogramEntry]
    public let reactedArticles: Int
    public let dismissedArticles: Int
    public let feedAffinityRows: Int
    public let topicAffinityRows: Int
    public let authorAffinityRows: Int
    public let signalWeightRows: Int
    public let overTaggedArticles: Int
    public let missingFeedKeys: Int
}

public struct TargetFeedCoverageSnapshot: Sendable, Hashable {
    public let familyName: String
    public let total: Int
    public let currentVersion: Int
    public let systemTagged: Int
    public let readyScored: Int
    public let reacted: Int
    public let dismissed: Int
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

    func listStaleArticleIDs(limit: Int = 25, targetFamiliesOnly: Bool = false) async -> [String] {
        let staleVersion = currentPersonalizationVersion
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.personalizationVersion < staleVersion },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )

        guard let articles = try? modelContext.fetch(descriptor) else {
            return []
        }

        var priorityTargetArticleIDs: [String] = []
        var targetArticleIDs: [String] = []
        var otherArticleIDs: [String] = []

        for article in articles {
            let context = makeArticleContext(from: article)
            let isTargetFamily = primaryPersonalizationTargetFeedFamily(
                feedTitle: context.feedTitle,
                siteHostname: context.siteHostname
            ) != nil

            if isTargetFamily {
                if article.reactionValue != nil || article.isDismissed {
                    priorityTargetArticleIDs.append(article.id)
                } else {
                    targetArticleIDs.append(article.id)
                }
            } else if !targetFamiliesOnly {
                otherArticleIDs.append(article.id)
            }
        }

        return Array((priorityTargetArticleIDs + targetArticleIDs + otherArticleIDs).prefix(limit))
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
    func targetFeedCoverageSnapshot() async -> [TargetFeedCoverageSnapshot] {
        struct Counts {
            var total = 0
            var currentVersion = 0
            var systemTagged = 0
            var readyScored = 0
            var reacted = 0
            var dismissed = 0
        }

        let descriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        var countsByFamilyName = Dictionary(uniqueKeysWithValues: personalizationTargetFeedFamilies.map { ($0.name, Counts()) })

        for article in articles {
            let context = makeArticleContext(from: article)
            guard let family = primaryPersonalizationTargetFeedFamily(
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
            if article.hasReadyScore {
                counts.readyScored += 1
            }
            if article.reactionValue != nil {
                counts.reacted += 1
            }
            if article.isDismissed {
                counts.dismissed += 1
            }
            countsByFamilyName[family.name] = counts
        }

        return personalizationTargetFeedFamilies.map { family in
            let counts = countsByFamilyName[family.name] ?? Counts()
            return TargetFeedCoverageSnapshot(
                familyName: family.name,
                total: counts.total,
                currentVersion: counts.currentVersion,
                systemTagged: counts.systemTagged,
                readyScored: counts.readyScored,
                reacted: counts.reacted,
                dismissed: counts.dismissed
            )
        }
    }

    func auditSnapshot() async -> PersonalizationAuditSnapshot {
        let descriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        let recentCutoff = Date().addingTimeInterval(-604_800)

        let readyArticles = articles.filter { $0.scoreStatusValue == .ready && $0.score != nil }
        let recentReadyArticles = readyArticles.filter { $0.fetchedAt >= recentCutoff }
        let currentVersionArticles = articles.count(where: { $0.personalizationVersion == currentPersonalizationVersion })
        let staleArticles = articles.count - currentVersionArticles

        func histogramEntries(for items: [Article]) -> [PersonalizationScoreHistogramEntry] {
            Dictionary(grouping: items.compactMap(\.score), by: { $0 })
                .map { PersonalizationScoreHistogramEntry(score: $0.key, count: $0.value.count) }
                .sorted { $0.score < $1.score }
        }

        let feedAffinityRows = ((try? modelContext.fetch(FetchDescriptor<FeedAffinity>())) ?? []).count
        let topicAffinityRows = ((try? modelContext.fetch(FetchDescriptor<TopicAffinity>())) ?? []).count
        let authorAffinityRows = ((try? modelContext.fetch(FetchDescriptor<AuthorAffinity>())) ?? []).count
        let signalWeightRows = ((try? modelContext.fetch(FetchDescriptor<SignalWeight>())) ?? []).count

        let missingFeedKeys = articles.reduce(into: 0) { count, article in
            if article.feed != nil && normalizedFeedKey(from: article.feed?.feedUrl) == nil {
                count += 1
            }
        }

        return PersonalizationAuditSnapshot(
            totalArticles: articles.count,
            currentVersionArticles: currentVersionArticles,
            staleArticles: staleArticles,
            totalReadyScores: readyArticles.count,
            readyScoreHistogram: histogramEntries(for: readyArticles),
            recentReadyScores: recentReadyArticles.count,
            recentReadyScoreHistogram: histogramEntries(for: recentReadyArticles),
            reactedArticles: articles.count(where: { $0.reactionValue != nil }),
            dismissedArticles: articles.count(where: \.isDismissed),
            feedAffinityRows: feedAffinityRows,
            topicAffinityRows: topicAffinityRows,
            authorAffinityRows: authorAffinityRows,
            signalWeightRows: signalWeightRows,
            overTaggedArticles: articles.count(where: { $0.systemTagIds.count > defaultDeterministicMaxSystemTags }),
            missingFeedKeys: missingFeedKeys
        )
    }
#endif

    func clearLearnedState() async throws {
        for row in (try? modelContext.fetch(FetchDescriptor<SignalWeight>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<TopicAffinity>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<AuthorAffinity>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<FeedAffinity>())) ?? [] {
            modelContext.delete(row)
        }
        try modelContext.save()
        try ensureDefaultSignalWeights()
    }

    fileprivate func listHistoricalLearningEvents() async -> [HistoricalLearningEvent] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .forward)]
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []
        var events: [HistoricalLearningEvent] = []

        for article in articles {
            let fallbackTimestamp = article.fetchedAt

            if let reactionValue = article.reactionValue {
                events.append(
                    HistoricalLearningEvent(
                        articleID: article.id,
                        kind: .reaction,
                        timestamp: article.reactionUpdatedAt ?? article.dismissedAt ?? article.readAt ?? fallbackTimestamp,
                        reactionValue: reactionValue,
                        reasonCodes: article.reactionReasonCodes?
                            .split(separator: ",")
                            .map(String.init) ?? []
                    )
                )
            }

            if let dismissedAt = article.dismissedAt {
                events.append(
                    HistoricalLearningEvent(
                        articleID: article.id,
                        kind: .dismiss,
                        timestamp: dismissedAt,
                        reactionValue: nil,
                        reasonCodes: []
                    )
                )
            }
        }

        return events.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.articleID < $1.articleID
            }
            return $0.timestamp < $1.timestamp
        }
    }

    func listAllArticleIDs() async -> [String] {
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }

    func needsHistoricalRebuild() async -> Bool {
        let articleDescriptor = FetchDescriptor<Article>()
        let articles = (try? modelContext.fetch(articleDescriptor)) ?? []

        if articles.contains(where: { article in
            article.personalizationVersion > 0 && article.personalizationVersion < currentPersonalizationVersion
        }) {
            return true
        }

        let signalWeights = (try? modelContext.fetch(FetchDescriptor<SignalWeight>())) ?? []
        if signalWeights.contains(where: { $0.sampleCount > 0 }) {
            return true
        }

        let topicRows = ((try? modelContext.fetch(FetchDescriptor<TopicAffinity>())) ?? []).count
        let authorRows = ((try? modelContext.fetch(FetchDescriptor<AuthorAffinity>())) ?? []).count
        let feedRows = ((try? modelContext.fetch(FetchDescriptor<FeedAffinity>())) ?? []).count
        return topicRows > 0 || authorRows > 0 || feedRows > 0
    }

    func impactedArticleIDs(for articleID: String, limit: Int) async -> [String] {
        guard let article = try? fetchArticle(articleID) else { return [] }

        let feedID = article.feed?.id
        let authorNormalized = normalizeAuthor(article.author)
        let tagIDs = Set((article.tags ?? []).map(\.id))
        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []

        var sameFeedIDs: [String] = []
        var otherImpactedIDs: [String] = []
        var seen: Set<String> = []

        for candidate in articles {
            guard candidate.id != article.id else { continue }

            let matchesFeed = feedID != nil && candidate.feed?.id == feedID
            let matchesAuthor = authorNormalized != nil && normalizeAuthor(candidate.author) == authorNormalized
            let candidateTagIDs = Set((candidate.tags ?? []).map(\.id))
            let matchesTags = !tagIDs.isEmpty && !candidateTagIDs.isDisjoint(with: tagIDs)

            guard matchesFeed || matchesAuthor || matchesTags else { continue }
            guard seen.insert(candidate.id).inserted else { continue }

            if matchesFeed {
                sameFeedIDs.append(candidate.id)
            } else {
                otherImpactedIDs.append(candidate.id)
            }
        }

        return Array((sameFeedIDs + otherImpactedIDs).prefix(limit))
    }

    func sameFeedArticleIDs(for articleID: String, limit: Int) async -> [String] {
        guard let article = try? fetchArticle(articleID),
              let feedID = article.feed?.id
        else {
            return []
        }

        let descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let articles = (try? modelContext.fetch(descriptor)) ?? []

        return articles
            .filter { $0.id != articleID && $0.feed?.id == feedID }
            .prefix(limit)
            .map(\.id)
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

    func listAllTagCandidates() async -> [DeterministicTagCandidate] {
        let descriptor = FetchDescriptor<Tag>(
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

    func rankedExistingTagSuggestionCandidates(
        title: String?,
        contentText: String?,
        limit: Int = tagSuggestionCandidateLimit
    ) async -> [ExistingTagSuggestionCandidate] {
        let scanLimit = max(limit, tagSuggestionCandidateScanLimit)
        let allTags = await listAllTagCandidates()
        let body = [title ?? "", String(contentText ?? "").truncated(to: 9_000)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let articleTokens = Set(tokenizeTagSuggestionMatch(body))
        let bodyLower = body.lowercased()
        let sortedTags = allTags.sorted {
            if $0.articleCount == $1.articleCount {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.articleCount > $1.articleCount
        }
        let candidateSlice = Array(sortedTags.prefix(scanLimit))
        let ranked: [(candidate: DeterministicTagCandidate, overlap: Int, phraseHit: Int, matchScore: Double)] =
            candidateSlice.map { candidate in
                let candidateTokens = tokenizeTagSuggestionMatch(candidate.name)
                let overlap = candidateTokens.reduce(0) { partial, token in
                    partial + (articleTokens.contains(token) ? 1 : 0)
                }
                let phraseHit = candidate.name.count >= 3 && bodyLower.contains(candidate.name.lowercased()) ? 1 : 0
                let matchScore = (Double(overlap) * 8) + (Double(phraseHit) * 5) + log1p(Double(candidate.articleCount))
                return (candidate, overlap, phraseHit, matchScore)
            }
            .sorted {
                if $0.matchScore == $1.matchScore {
                    if $0.candidate.articleCount == $1.candidate.articleCount {
                        return $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
                    }
                    return $0.candidate.articleCount > $1.candidate.articleCount
                }
                return $0.matchScore > $1.matchScore
            }

        var selected: [ExistingTagSuggestionCandidate] = ranked
            .filter { $0.overlap > 0 || $0.phraseHit > 0 }
            .prefix(limit)
            .map {
                ExistingTagSuggestionCandidate(
                    id: $0.candidate.id,
                    name: $0.candidate.name,
                    matchScore: $0.matchScore,
                    articleCount: $0.candidate.articleCount
                )
            }

        if selected.count < limit {
            var used = Set(selected.map(\.id))
            for entry in ranked {
                guard selected.count < limit else { break }
                guard used.insert(entry.candidate.id).inserted else { continue }
                selected.append(
                    ExistingTagSuggestionCandidate(
                        id: entry.candidate.id,
                        name: entry.candidate.name,
                        matchScore: log1p(Double(entry.candidate.articleCount)),
                        articleCount: entry.candidate.articleCount
                    )
                )
            }
        }

        return selected
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

    func replaceTagSuggestions(
        articleID: String,
        suggestions: [SuggestedTagCandidate],
        sourceProvider: String?,
        sourceModel: String?
    ) async throws {
        let descriptor = FetchDescriptor<ArticleTagSuggestion>(
            predicate: #Predicate<ArticleTagSuggestion> { $0.articleId == articleID }
        )
        let existingRows = (try? modelContext.fetch(descriptor)) ?? []
        let existingByNormalized = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.nameNormalized, $0) })
        let now = Date()
        let normalizedIncoming = Set(suggestions.map { ArticleTagSuggestion.normalizeName($0.name) })

        for suggestion in suggestions {
            let normalizedName = ArticleTagSuggestion.normalizeName(suggestion.name)
            guard !normalizedName.isEmpty else { continue }

            if let existing = existingByNormalized[normalizedName] {
                existing.name = suggestion.name
                existing.confidence = suggestion.confidence
                existing.sourceProvider = sourceProvider
                existing.sourceModel = sourceModel
                existing.updatedAt = now
            } else {
                modelContext.insert(
                    ArticleTagSuggestion(
                        articleId: articleID,
                        name: suggestion.name,
                        confidence: suggestion.confidence,
                        sourceProvider: sourceProvider,
                        sourceModel: sourceModel,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
        }

        for row in existingRows {
            guard row.dismissedAt == nil else { continue }
            if !normalizedIncoming.contains(row.nameNormalized) {
                modelContext.delete(row)
            }
        }

        try modelContext.save()
    }

    func clearActiveTagSuggestions(articleID: String) async throws {
        let descriptor = FetchDescriptor<ArticleTagSuggestion>(
            predicate: #Predicate<ArticleTagSuggestion> { $0.articleId == articleID }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows where row.dismissedAt == nil {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    func dismissTagSuggestion(articleID: String, suggestionID: String) async throws {
        let descriptor = FetchDescriptor<ArticleTagSuggestion>(
            predicate: #Predicate<ArticleTagSuggestion> { $0.id == suggestionID && $0.articleId == articleID }
        )
        guard let suggestion = try modelContext.fetch(descriptor).first else {
            return
        }

        suggestion.dismissedAt = Date()
        suggestion.updatedAt = Date()
        try modelContext.save()
    }

    func acceptTagSuggestion(articleID: String, suggestionID: String) async throws -> String? {
        let suggestionDescriptor = FetchDescriptor<ArticleTagSuggestion>(
            predicate: #Predicate<ArticleTagSuggestion> { $0.id == suggestionID && $0.articleId == articleID }
        )
        guard let suggestion = try modelContext.fetch(suggestionDescriptor).first else {
            return nil
        }

        let article = try fetchArticle(articleID)
        let normalizedName = Tag.normalizeName(suggestion.name)
        let tagDescriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.nameNormalized == normalizedName }
        )

        let tag: Tag
        if let existing = try modelContext.fetch(tagDescriptor).first {
            tag = existing
        } else {
            tag = Tag(
                name: suggestion.name,
                slug: Tag.normalizeSlug(suggestion.name),
                isCanonical: false
            )
            modelContext.insert(tag)
        }

        if article.tags == nil {
            article.tags = []
        }
        if !(article.tags?.contains(where: { $0.id == tag.id }) ?? false) {
            article.tags?.append(tag)
        }

        modelContext.delete(suggestion)
        try modelContext.save()
        return tag.id
    }

    func persistScoreAssist(articleID: String, output: ScoreAssistOutput?) async throws {
        let article = try fetchArticle(articleID)

        if let output {
            article.scoreAssistExplanation = output.explanation
            article.scoreAssistProvider = output.provider.rawValue
            article.scoreAssistModel = output.modelIdentifier
            article.scoreAssistAdjustment = output.adjustment
            article.scoreAssistGeneratedAt = Date()
        } else {
            article.scoreAssistExplanation = nil
            article.scoreAssistProvider = nil
            article.scoreAssistModel = nil
            article.scoreAssistAdjustment = nil
            article.scoreAssistGeneratedAt = nil
        }

        article.refreshQueryState()
        try modelContext.save()
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
            let reasonCodes = article.reactionReasonCodes?
                .split(separator: ",")
                .map(String.init) ?? []
            guard hasSourceReason(reasonCodes) else { continue }
            feedbackCount += 1
            let voteWeight = sourceReputationVoteWeight
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

    func feedAffinity(for feedKey: String?) async -> FeedAffinity? {
        guard let feedKey, !feedKey.isEmpty else { return nil }
        let descriptor = FetchDescriptor<FeedAffinity>(
            predicate: #Predicate<FeedAffinity> { $0.feedKey == feedKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func persistScore(articleID: String, algorithmicScore: AlgorithmicScore) async throws {
        let article = try fetchArticle(articleID)
        let explanation = algorithmicScoreExplanation(algorithmicScore)

        article.score = algorithmicScore.status == .ready ? algorithmicScore.score : nil
        article.scoreLabel = algorithmicScore.status == .ready
            ? algorithmicScoreLabel(algorithmicScore)
            : "Learning your preferences"
        article.scoreConfidence = algorithmicScore.confidence
        article.scorePreferenceConfidence = algorithmicScore.preferenceConfidence
        article.scoreWeightedAverage = algorithmicScore.weightedAverage
        article.scoreStatus = algorithmicScore.status.rawValue
        article.signalScoresJson = encodeJSON(algorithmicScore.signals)
        article.scoreExplanation = algorithmicScore.status == .ready ? explanation : nil
        article.personalizationVersion = currentPersonalizationVersion
        article.markScorePrepared(revision: max(article.contentRevision, currentPersonalizationVersion))
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
            let centeredValue = signalScore.normalizedValue - 0.5
            let error = Double(direction) * centeredValue
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

    func updateFeedAffinity(
        for feedKey: String,
        direction: Int,
        multiplier: Double
    ) async throws {
        let row = try feedAffinityRow(for: feedKey)
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
            feedKey: article.feed.flatMap { normalizedFeedKey(from: $0.feedUrl) },
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
    private let modelContainer: ModelContainer
    private let repository: LocalPersonalizationRepository
    private let generationCoordinator: (any AIGenerationCoordinating)?
    private var isRebuildingHistoricalState = false

    public init(
        modelContainer: ModelContainer,
        keychainService: String = "com.nebularnews.ios",
        generationCoordinator: (any AIGenerationCoordinating)? = nil
    ) {
        self.modelContainer = modelContainer
        self.repository = LocalPersonalizationRepository(modelContainer: modelContainer)
        self.generationCoordinator = generationCoordinator
            ?? AIGenerationCoordinator(modelContainer: modelContainer, keychainService: keychainService)
    }

    public func bootstrap() async {
        try? await repository.bootstrapStarterData()
    }

    @discardableResult
    public func processPendingArticles(limit: Int = 25) async -> Int {
        await bootstrap()
        _ = await ensureHistoricalRebuildIfNeeded()
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
    public func reprocessTargetFeedFamilies(batchSize: Int = 200) async -> Int {
        await bootstrap()
        _ = await ensureHistoricalRebuildIfNeeded(batchSize: batchSize)
        var totalProcessed = 0

        while true {
            let articleIDs = await repository.listStaleArticleIDs(limit: batchSize, targetFamiliesOnly: true)
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

    public func targetFeedCoverageSnapshot() async -> [TargetFeedCoverageSnapshot] {
        await bootstrap()
        return await repository.targetFeedCoverageSnapshot()
    }

    public func auditSnapshot() async -> PersonalizationAuditSnapshot {
        await bootstrap()
        return await repository.auditSnapshot()
    }
#endif

    @discardableResult
    public func rebuildPersonalizationFromHistory(batchSize: Int = 200, force: Bool = false) async -> Int {
        await bootstrap()
        return await ensureHistoricalRebuildIfNeeded(batchSize: batchSize, force: force)
    }

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
        try await retagAndScoreArticle(
            articleID: articleID,
            skipTagSuggestions: false,
            persistScoreAssist: true
        )
    }

    public func prepareVisibleScore(articleID: String) async throws {
        await bootstrap()
        try await retagAndScoreArticle(
            articleID: articleID,
            skipTagSuggestions: true,
            persistScoreAssist: false
        )
    }

    private func retagAndScoreArticle(
        articleID: String,
        skipTagSuggestions: Bool,
        persistScoreAssist: Bool
    ) async throws {
        guard let snapshot = await repository.storedArticleSnapshot(for: articleID) else { return }

        let evaluation = await deterministicTagEvaluation(for: snapshot.context)
        try await repository.applySystemTags(articleID: articleID, desiredTagIDs: evaluation.decisions.map(\.tagId))
        if !skipTagSuggestions,
           let refreshedSnapshot = await repository.storedArticleSnapshot(for: articleID) {
            try await refreshTagSuggestionsIfNeeded(snapshot: refreshedSnapshot)
        }
        try await rescoreArticle(articleID: articleID, persistScoreAssist: persistScoreAssist)
    }

    public func rescoreArticle(articleID: String) async throws {
        await bootstrap()
        try await rescoreArticle(articleID: articleID, persistScoreAssist: true)
    }

    private func rescoreArticle(articleID: String, persistScoreAssist: Bool) async throws {
        guard let snapshot = await repository.storedArticleSnapshot(for: articleID) else { return }
        let context = snapshot.context

        let topicAffinityMap = await repository.topicAffinityMap(for: context.tags.map(\.normalizedName))
        let authorAffinity = await repository.authorAffinity(for: context.authorNormalized)
        let feedAffinity = await repository.feedAffinity(for: context.feedKey)
        let feedReputation = await repository.feedReputation(feedID: context.feedID)
        let signalScores = extractSignals(
            context: context,
            topicAffinities: topicAffinityMap,
            authorAffinity: authorAffinity,
            feedAffinity: feedAffinity,
            feedReputation: feedReputation
        )
        let weights = await repository.loadSignalWeights()
        let algorithmicScore = computeAlgorithmicScore(signals: signalScores, weights: weights)
        try await repository.persistScore(articleID: articleID, algorithmicScore: algorithmicScore)
        if persistScoreAssist {
            let scoreAssist = try await generateScoreAssistIfNeeded(
                context: context,
                algorithmicScore: algorithmicScore
            )
            try await repository.persistScoreAssist(articleID: articleID, output: scoreAssist)
        }
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

        await applyReactionLearning(snapshot: snapshot, finalValue: finalValue, reasonCodes: reasonCodes)

        try? await rescoreArticle(articleID: articleID)
        await rescoreRelatedArticles(for: articleID)
    }

    public func processDismissChange(
        articleID: String,
        previousDismissedAt: Date?,
        newDismissedAt: Date?
    ) async {
        await bootstrap()
        guard previousDismissedAt == nil,
              newDismissedAt != nil
        else {
            return
        }

        guard let snapshot = await refreshSnapshot(articleID: articleID) else {
            return
        }

        await applyDismissLearning(snapshot: snapshot)

        try? await rescoreArticle(articleID: articleID)
        await rescoreSameFeedArticles(for: articleID)
    }

    public func acceptTagSuggestion(articleID: String, suggestionID: String) async {
        await bootstrap()
        guard (try? await repository.acceptTagSuggestion(articleID: articleID, suggestionID: suggestionID)) != nil else {
            return
        }
        try? await rescoreArticle(articleID: articleID)
    }

    public func dismissTagSuggestion(articleID: String, suggestionID: String) async {
        await bootstrap()
        try? await repository.dismissTagSuggestion(articleID: articleID, suggestionID: suggestionID)
    }

    private func refreshSnapshot(
        articleID: String,
        skipTagSuggestions: Bool = false,
        persistScoreAssist: Bool = true
    ) async -> StoredArticlePersonalizationSnapshot? {
        let needsRetagging = await repository.needsRetagging(articleID: articleID)
        if needsRetagging {
            try? await retagAndScoreArticle(
                articleID: articleID,
                skipTagSuggestions: skipTagSuggestions,
                persistScoreAssist: persistScoreAssist
            )
        }

        guard var snapshot = await repository.storedArticleSnapshot(for: articleID) else {
            return nil
        }

        if snapshot.signalScores.isEmpty {
            try? await rescoreArticle(articleID: articleID, persistScoreAssist: persistScoreAssist)
            if let refreshedSnapshot = await repository.storedArticleSnapshot(for: articleID) {
                snapshot = refreshedSnapshot
            }
        }

        return snapshot
    }

    private func applyReactionLearning(
        snapshot: StoredArticlePersonalizationSnapshot,
        finalValue: Int,
        reasonCodes: [ArticleReactionReasonCode]
    ) async {
        let context = snapshot.context
        let signalScores = snapshot.signalScores
        guard !signalScores.isEmpty else { return }

        try? await repository.updateWeightsFromReaction(
            direction: finalValue,
            signalScores: signalScores,
            reasonCodes: reasonCodes
        )

        let feedAffinityMultiplier = hasFeedAffinityReason(reasonCodes) ? explicitAffinityMultiplier : implicitAffinityMultiplier
        if let feedKey = context.feedKey, !feedKey.isEmpty {
            try? await repository.updateFeedAffinity(
                for: feedKey,
                direction: finalValue,
                multiplier: feedAffinityMultiplier
            )
        }

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
    }

    private func applyDismissLearning(snapshot: StoredArticlePersonalizationSnapshot) async {
        guard let feedKey = snapshot.context.feedKey, !feedKey.isEmpty else {
            return
        }

        try? await repository.updateFeedAffinity(
            for: feedKey,
            direction: -1,
            multiplier: dismissAffinityMultiplier
        )
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

    private func rescoreSameFeedArticles(for articleID: String) async {
        let impactedIDs = await repository.sameFeedArticleIDs(for: articleID, limit: impactedArticleRescoreLimit)

        for impactedID in impactedIDs {
            if await repository.needsRetagging(articleID: impactedID) {
                try? await retagAndScoreArticle(articleID: impactedID)
            } else {
                try? await rescoreArticle(articleID: impactedID)
            }
        }
    }

    private func ensureHistoricalRebuildIfNeeded(
        batchSize: Int = 200,
        force: Bool = false
    ) async -> Int {
        guard !isRebuildingHistoricalState else { return 0 }

        let settingsRepository = repositorySettingsRepository()
        let currentVersion = await settingsRepository.personalizationRebuildVersion()
        guard force || currentVersion < currentPersonalizationVersion else {
            return 0
        }
        let needsRebuild = force ? true : await repository.needsHistoricalRebuild()
        guard needsRebuild else {
            await settingsRepository.setPersonalizationRebuildVersion(currentPersonalizationVersion)
            return 0
        }

        isRebuildingHistoricalState = true
        defer { isRebuildingHistoricalState = false }

        let processed = await rebuildHistoricalState(batchSize: batchSize)
        await settingsRepository.setPersonalizationRebuildVersion(currentPersonalizationVersion)
        return processed
    }

    private func rebuildHistoricalState(batchSize: Int) async -> Int {
        try? await repository.clearLearnedState()

        let articleIDs = await repository.listAllArticleIDs()
        var processed = 0

        for chunkStart in stride(from: 0, to: articleIDs.count, by: max(1, batchSize)) {
            let chunk = articleIDs[chunkStart..<min(chunkStart + max(1, batchSize), articleIDs.count)]
            for articleID in chunk {
                try? await retagAndScoreArticle(
                    articleID: articleID,
                    skipTagSuggestions: true,
                    persistScoreAssist: false
                )
                processed += 1
            }
        }

        let events = await repository.listHistoricalLearningEvents()
        for event in events {
            guard await refreshSnapshot(
                articleID: event.articleID,
                skipTagSuggestions: true,
                persistScoreAssist: false
            ) != nil else {
                continue
            }

            try? await rescoreArticle(articleID: event.articleID, persistScoreAssist: false)
            guard let rescoredSnapshot = await repository.storedArticleSnapshot(for: event.articleID) else {
                continue
            }

            switch event.kind {
            case .reaction:
                guard let finalValue = event.reactionValue else { continue }
                await applyReactionLearning(
                    snapshot: rescoredSnapshot,
                    finalValue: finalValue,
                    reasonCodes: event.reasonCodes
                )
            case .dismiss:
                await applyDismissLearning(snapshot: rescoredSnapshot)
            }
        }

        for chunkStart in stride(from: 0, to: articleIDs.count, by: max(1, batchSize)) {
            let chunk = articleIDs[chunkStart..<min(chunkStart + max(1, batchSize), articleIDs.count)]
            for articleID in chunk {
                try? await rescoreArticle(articleID: articleID, persistScoreAssist: false)
            }
        }

        return processed
    }

    private func refreshTagSuggestionsIfNeeded(snapshot: StoredArticlePersonalizationSnapshot) async throws {
        guard let generationCoordinator else {
            try await repository.clearActiveTagSuggestions(articleID: snapshot.context.id)
            return
        }

        let context = snapshot.context
        let attachedTagNames = context.tags.map(\.name)
        guard shouldGenerateTagSuggestions(context: context, attachedTagNames: attachedTagNames) else {
            try await repository.clearActiveTagSuggestions(articleID: context.id)
            return
        }

        let existingCandidates = await repository.rankedExistingTagSuggestionCandidates(
            title: context.title,
            contentText: context.contentText,
            limit: tagSuggestionCandidateLimit
        )

        let input = TagSuggestionInput(
            articleID: context.id,
            title: context.title,
            canonicalURL: context.canonicalURL,
            contentText: context.contentText,
            feedTitle: context.feedTitle,
            siteHostname: context.siteHostname,
            attachedTags: attachedTagNames,
            existingCandidates: existingCandidates,
            maxSuggestions: maxGeneratedTagSuggestions
        )

        let allTags = await repository.listAllTagCandidates()
        guard let generatedOutput = try await generationCoordinator.generateTagSuggestions(input: input) else {
            return
        }
        let filteredSuggestions = filterGeneratedSuggestions(
            generatedOutput.suggestions,
            input: input,
            allTagCandidates: allTags
        )

        try await repository.replaceTagSuggestions(
            articleID: context.id,
            suggestions: filteredSuggestions,
            sourceProvider: generatedOutput.provider.rawValue,
            sourceModel: generatedOutput.modelIdentifier
        )
    }

    private func generateScoreAssistIfNeeded(
        context: PersonalizationArticleContext,
        algorithmicScore: AlgorithmicScore
    ) async throws -> ScoreAssistOutput? {
        guard let generationCoordinator,
              algorithmicScore.status == .ready
        else {
            return nil
        }

        let settingsRepo = repositorySettingsRepository()
        let settings = await settingsRepo.getOrCreate()
        guard settings.scoreAssistMode != AIScoreAssistMode.algorithmicOnly else {
            return nil
        }

        let explanation = algorithmicScoreExplanation(algorithmicScore)
        let input = ScoreAssistInput(
            title: context.title,
            canonicalURL: context.canonicalURL,
            contentText: context.contentText,
            algorithmicScore: algorithmicScore.score,
            algorithmicExplanation: explanation,
            signalSummary: algorithmicSignalSummary(algorithmicScore.signals),
            scoreAssistMode: settings.scoreAssistMode
        )

        let rawOutput = try await generationCoordinator.generateScoreAssist(input: input)
        guard let rawOutput else { return nil }

        let normalizedAdjustment = settings.scoreAssistMode == AIScoreAssistMode.hybridAdjust
            ? rawOutput.adjustment
            : 0
        return ScoreAssistOutput(
            explanation: rawOutput.explanation,
            adjustment: normalizedAdjustment,
            provider: rawOutput.provider,
            modelIdentifier: rawOutput.modelIdentifier
        )
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
        feedAffinity: FeedAffinity?,
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

        if let feedAffinity {
            signals.append(
                StoredSignalScore(
                    signal: .feedAffinity,
                    rawValue: feedAffinity.affinity,
                    normalizedValue: sigmoid(feedAffinity.affinity, steepness: 2),
                    isDataBacked: true
                )
            )
        }

        if feedReputation.weightedFeedbackCount >= 3.0 {
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

        return signals
    }

    private func repositorySettingsRepository() -> LocalSettingsRepository {
        LocalSettingsRepository(modelContainer: modelContainer)
    }
}

private let tagSuggestionStopWords: Set<String> = [
    "the", "and", "for", "with", "from", "that", "this", "into", "your", "about", "their", "will", "have", "has",
    "are", "was", "were", "not", "you", "its", "new", "how", "why", "who", "what", "when", "where", "can",
    "could", "should", "would", "over", "under", "more", "less"
]

private let genericSuggestionNames: Set<String> = [
    "news", "update", "article", "articles", "story", "stories", "briefing", "report"
]

private func algorithmicScoreLabel(_ score: AlgorithmicScore) -> String {
    let confidencePercent = Int((score.confidence * 100).rounded())
    return "Algorithmic (\(confidencePercent)% confidence)"
}

private func algorithmicScoreExplanation(_ score: AlgorithmicScore) -> String {
    """
    \(algorithmicScoreLabel(score))
    Weighted average: \(formatDecimal(score.weightedAverage))
    \(algorithmicSignalSummary(score.signals).isEmpty ? "" : "\n\(algorithmicSignalSummary(score.signals))")
    """
}

private func algorithmicSignalSummary(_ signals: [StoredSignalScore]) -> String {
    signals
        .map { signal in
            "• \(signal.signal.rawValue): \(formatDecimal(signal.normalizedValue)) (raw: \(formatDecimal(signal.rawValue)))"
        }
        .joined(separator: "\n")
}

private func tokenizeTagSuggestionMatch(_ value: String) -> [String] {
    Array(Set(
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 3 && !tagSuggestionStopWords.contains($0) }
    ))
}

private func tagSuggestionTokenSet(_ value: String?) -> Set<String> {
    Set(tokenizeTagSuggestionMatch(value ?? ""))
}

private func shouldGenerateTagSuggestions(
    context: PersonalizationArticleContext,
    attachedTagNames: [String]
) -> Bool {
    guard let contentText = context.contentText,
          !contentText.isEmpty
    else {
        return false
    }

    return attachedTagNames.count < minimumAttachedTagsForSuggestionSkip
}

private func filterGeneratedSuggestions(
    _ suggestions: [SuggestedTagCandidate],
    input: TagSuggestionInput,
    allTagCandidates: [DeterministicTagCandidate]
) -> [SuggestedTagCandidate] {
    let attachedNames = Set(input.attachedTags.map(Tag.normalizeName))
    let sourceTokenSets = [
        tagSuggestionTokenSet(input.feedTitle),
        tagSuggestionTokenSet(input.siteHostname),
        tagSuggestionTokenSet(URL(string: input.canonicalURL ?? "")?.host?.components(separatedBy: ".").dropLast().joined(separator: " "))
    ].filter { !$0.isEmpty }

    var accepted: [SuggestedTagCandidate] = []
    var acceptedTokenSets: [Set<String>] = []

    for suggestion in suggestions {
        let normalizedName = ArticleTagSuggestion.normalizeName(suggestion.name)
        let wordCount = normalizedName.split(separator: " ").count
        let tokens = tagSuggestionTokenSet(normalizedName)

        guard suggestion.confidence >= strongSuggestionConfidenceFloor,
              !normalizedName.isEmpty,
              wordCount >= 1,
              wordCount <= 3,
              !genericSuggestionNames.contains(normalizedName),
              !attachedNames.contains(normalizedName),
              !tokens.isEmpty,
              !matchesExistingSuggestionName(
                normalizedName,
                tokens: tokens,
                existingCandidates: allTagCandidates
              ),
              !matchesSourceName(tokens: tokens, sourceTokenSets: sourceTokenSets),
              !accepted.contains(where: { ArticleTagSuggestion.normalizeName($0.name) == normalizedName }),
              !acceptedTokenSets.contains(where: { tokenOverlapRatio($0, tokens) >= 0.75 })
        else {
            continue
        }

        accepted.append(SuggestedTagCandidate(name: normalizedSuggestionName(suggestion.name), confidence: suggestion.confidence))
        acceptedTokenSets.append(tokens)

        if accepted.count >= maxGeneratedTagSuggestions {
            break
        }
    }

    return accepted
}

private func matchesExistingSuggestionName(
    _ normalizedName: String,
    tokens: Set<String>,
    existingCandidates: [DeterministicTagCandidate]
) -> Bool {
    existingCandidates.contains { candidate in
        if candidate.normalizedName == normalizedName || candidate.slug == Tag.normalizeSlug(normalizedName) {
            return true
        }

        let candidateTokens = tagSuggestionTokenSet(candidate.name)
        return tokenOverlapRatio(tokens, candidateTokens) >= 0.75
    }
}

private func matchesSourceName(tokens: Set<String>, sourceTokenSets: [Set<String>]) -> Bool {
    sourceTokenSets.contains { tokenOverlapRatio(tokens, $0) >= 0.75 }
}

private func tokenOverlapRatio(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    let intersectionCount = lhs.intersection(rhs).count
    return Double(intersectionCount) / Double(max(lhs.count, rhs.count))
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

func normalizedFeedKey(from value: String?) -> String? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty
    else {
        return nil
    }

    if let components = URLComponents(string: rawValue),
       let host = components.host?.lowercased() {
        let normalizedHost = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let normalizedPath = components.path
            .lowercased()
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

        let key = normalizedHost + normalizedPath
        return key.isEmpty ? nil : key
    }

    let normalized = rawValue
        .lowercased()
        .replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[?#].*$", with: "", options: .regularExpression)
        .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

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
