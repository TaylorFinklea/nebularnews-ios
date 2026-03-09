import Foundation

private let titlePhraseWeight = 1.0
private let urlPhraseWeight = 0.4
private let contentPhraseWeight = 0.35
private let titleTokenWeight = 0.3
private let titleTokenCap = 0.6
private let contentTokenWeight = 0.08
private let contentTokenCap = 0.4
private let feedPriorBonus = 0.10
private let feedPriorMinArticles = 3
private let feedPriorMinRatio = 0.2
private let sourceBaselineScore = 1.05
private let sourceProfileBonus = 0.20

public let defaultDeterministicTagAttachThreshold = 0.65
public let defaultDeterministicMaxSystemTags = 3

public struct DeterministicTaggingContext: Sendable {
    public let title: String?
    public let canonicalURL: String?
    public let contentText: String?
    public let feedTitle: String?
    public let siteHostname: String?

    public init(
        title: String?,
        canonicalURL: String?,
        contentText: String?,
        feedTitle: String?,
        siteHostname: String?
    ) {
        self.title = title
        self.canonicalURL = canonicalURL
        self.contentText = contentText
        self.feedTitle = feedTitle
        self.siteHostname = siteHostname
    }
}

public struct DeterministicTagCandidate: Sendable, Hashable {
    public let id: String
    public let name: String
    public let normalizedName: String
    public let slug: String
    public let articleCount: Int

    public init(id: String, name: String, normalizedName: String, slug: String, articleCount: Int) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.slug = slug
        self.articleCount = articleCount
    }
}

public struct DeterministicTagDecision: Sendable, Hashable {
    public let tagId: String
    public let score: Double
    public let confidence: Double
    public let features: [String]

    public init(tagId: String, score: Double, confidence: Double, features: [String]) {
        self.tagId = tagId
        self.score = score
        self.confidence = confidence
        self.features = features
    }
}

public struct DeterministicTagEvaluation: Sendable, Hashable {
    public let matchedSourceProfiles: [String]
    public let decisions: [DeterministicTagDecision]

    public init(matchedSourceProfiles: [String], decisions: [DeterministicTagDecision]) {
        self.matchedSourceProfiles = matchedSourceProfiles
        self.decisions = decisions
    }
}

public struct FeedTagPrior: Sendable, Hashable {
    public let taggedArticleCount: Int
    public let ratio: Double

    public init(taggedArticleCount: Int, ratio: Double) {
        self.taggedArticleCount = taggedArticleCount
        self.ratio = ratio
    }
}

private func normalizeWhitespace(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private func normalizeText(_ value: String?) -> String {
    let raw = value ?? ""
    let normalized = raw
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return " \(normalized) "
}

func normalizeFeedIdentityText(_ value: String?) -> String {
    (value ?? "")
        .lowercased()
        .replacingOccurrences(of: "&#?[a-z0-9]+;", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizeFeedIdentityHost(_ value: String?) -> String {
    (value ?? "")
        .lowercased()
        .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func tokenize(_ value: String?) -> [String] {
    Array(Set(
        normalizeText(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
    ))
}

private func hasPhrase(_ haystack: String, _ needle: String) -> Bool {
    !needle.isEmpty && haystack.contains(" \(needle) ")
}

private func overlapCount(_ candidateTokens: [String], haystackTokens: Set<String>) -> Int {
    candidateTokens.reduce(0) { partial, token in
        partial + (haystackTokens.contains(token) ? 1 : 0)
    }
}

private func hostMatches(actualHost: String, expectedHost: String) -> Bool {
    let actual = normalizeFeedIdentityHost(actualHost)
    let expected = normalizeFeedIdentityHost(expectedHost)
    guard !actual.isEmpty, !expected.isEmpty else { return false }
    return actual == expected || actual.hasSuffix(".\(expected)")
}

private func matchesFeedIdentity(
    feedTitle: String?,
    siteHostname: String?,
    feedTitleAliases: [String],
    siteHosts: [String]
) -> Bool {
    let normalizedFeedTitle = normalizeFeedIdentityText(feedTitle)
    let normalizedHost = normalizeFeedIdentityHost(siteHostname)

    let matchesTitle = feedTitleAliases
        .map(normalizeFeedIdentityText)
        .contains(normalizedFeedTitle)
    let matchesHost = siteHosts.contains { hostMatches(actualHost: normalizedHost, expectedHost: $0) }
    return matchesTitle || matchesHost
}

func matchingPersonalizationTargetFeedFamilies(feedTitle: String?, siteHostname: String?) -> [PersonalizationTargetFeedFamily] {
    personalizationTargetFeedFamilies.filter { family in
        matchesFeedIdentity(
            feedTitle: feedTitle,
            siteHostname: siteHostname,
            feedTitleAliases: family.feedTitleAliases,
            siteHosts: family.siteHosts
        )
    }
}

func primaryPersonalizationTargetFeedFamily(feedTitle: String?, siteHostname: String?) -> PersonalizationTargetFeedFamily? {
    matchingPersonalizationTargetFeedFamilies(feedTitle: feedTitle, siteHostname: siteHostname).first
}

private func matchingSourceProfiles(for context: DeterministicTaggingContext) -> [DeterministicTagSourceProfile] {
    let normalizedFeedTitle = normalizeFeedIdentityText(context.feedTitle)
    let normalizedHost = normalizeFeedIdentityHost(context.siteHostname)

    return deterministicTagSourceProfiles.filter { profile in
        matchesFeedIdentity(
            feedTitle: normalizedFeedTitle,
            siteHostname: normalizedHost,
            feedTitleAliases: profile.feedTitles,
            siteHosts: profile.siteHosts
        )
    }
}

private func mergeDecision(
    existing: DeterministicTagDecision?,
    incoming: DeterministicTagDecision
) -> DeterministicTagDecision {
    guard let existing else { return incoming }

    return DeterministicTagDecision(
        tagId: existing.tagId,
        score: max(existing.score, incoming.score),
        confidence: max(existing.confidence, incoming.confidence),
        features: Array(Set(existing.features + incoming.features)).sorted()
    )
}

private func hasLexicalEvidence(_ features: [String]) -> Bool {
    features.contains { feature in
        feature == "title_phrase" ||
        feature == "url_phrase" ||
        feature == "content_phrase" ||
        feature.hasPrefix("title_overlap:") ||
        feature.hasPrefix("content_overlap:")
    }
}

public func scoreDeterministicTagCandidate(
    candidate: DeterministicTagCandidate,
    context: DeterministicTaggingContext,
    feedPrior: FeedTagPrior?
) -> DeterministicTagDecision {
    let normalizedName = normalizeWhitespace(candidate.normalizedName).lowercased()
    let keywordPhrases = Array(Set((deterministicTagKeywordsBySlug[candidate.slug] ?? []).map {
        normalizeWhitespace($0).lowercased()
    }))
    let candidatePhrases = Array(Set([normalizedName] + keywordPhrases))
    let titleText = normalizeText([context.title, context.feedTitle].compactMap { $0 }.joined(separator: " "))
    let contentText = normalizeText(String(context.contentText ?? "").truncated(to: 12_000))

    let url = context.canonicalURL ?? ""
    let normalizedURLText: String
    if let parsed = URL(string: url) {
        normalizedURLText = normalizeText([
            context.siteHostname,
            parsed.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression),
            parsed.path
        ].compactMap { $0 }.joined(separator: " "))
    } else {
        normalizedURLText = normalizeText([context.siteHostname, url].compactMap { $0 }.joined(separator: " "))
    }

    let candidateTokens = Array(Set(candidatePhrases.flatMap { tokenize($0) }))
    let titleLikeTokens = Set(tokenize(context.title) + tokenize(context.feedTitle))
    let contentTokens = Set(tokenize(String(context.contentText ?? "").truncated(to: 12_000)))

    var score = 0.0
    var features: [String] = []

    if candidatePhrases.contains(where: { hasPhrase(titleText, $0) }) {
        score += titlePhraseWeight
        features.append("title_phrase")
    }

    if candidatePhrases.contains(where: { hasPhrase(normalizedURLText, $0) }) ||
        (!candidate.slug.isEmpty && url.lowercased().contains(candidate.slug)) {
        score += urlPhraseWeight
        features.append("url_phrase")
    }

    if candidatePhrases.contains(where: { hasPhrase(contentText, $0) }) {
        score += contentPhraseWeight
        features.append("content_phrase")
    }

    let titleOverlap = overlapCount(candidateTokens, haystackTokens: titleLikeTokens)
    if titleOverlap > 0 {
        score += min(titleTokenCap, Double(titleOverlap) * titleTokenWeight)
        features.append("title_overlap:\(titleOverlap)")
    }

    let contentOverlap = overlapCount(candidateTokens, haystackTokens: contentTokens)
    if contentOverlap > 0 {
        score += min(contentTokenCap, Double(contentOverlap) * contentTokenWeight)
        features.append("content_overlap:\(contentOverlap)")
    }

    if let feedPrior,
       hasLexicalEvidence(features),
       feedPrior.taggedArticleCount >= feedPriorMinArticles,
       feedPrior.ratio >= feedPriorMinRatio {
        score += feedPriorBonus
        features.append("feed_prior")
    }

    return DeterministicTagDecision(
        tagId: candidate.id,
        score: (score * 10_000).rounded() / 10_000,
        confidence: min(1, (score * 10_000).rounded() / 10_000),
        features: features
    )
}

public func generateDeterministicTagEvaluation(
    candidates: [DeterministicTagCandidate],
    context: DeterministicTaggingContext,
    feedPriorsByTagId: [String: FeedTagPrior],
    attachThreshold: Double = defaultDeterministicTagAttachThreshold,
    maxTags: Int = defaultDeterministicMaxSystemTags
) -> DeterministicTagEvaluation {
    let matchedProfiles = matchingSourceProfiles(for: context)
    let candidatesBySlug = Dictionary(uniqueKeysWithValues: candidates.map { ($0.slug, $0) })

    var decisionsByTagID: [String: DeterministicTagDecision] = [:]

    for candidate in candidates {
        let decision = scoreDeterministicTagCandidate(
            candidate: candidate,
            context: context,
            feedPrior: feedPriorsByTagId[candidate.id]
        )

        if decision.score >= attachThreshold {
            decisionsByTagID[candidate.id] = mergeDecision(
                existing: decisionsByTagID[candidate.id],
                incoming: decision
            )
        }
    }

    for profile in matchedProfiles {
        if let baselineSlug = profile.baselineTagSlugs.first,
           let candidate = candidatesBySlug[baselineSlug] {
            let directDecision = DeterministicTagDecision(
                tagId: candidate.id,
                score: sourceBaselineScore,
                confidence: 1,
                features: ["source_profile_baseline:\(profile.name)"]
            )

            decisionsByTagID[candidate.id] = mergeDecision(
                existing: decisionsByTagID[candidate.id],
                incoming: directDecision
            )
        }

        for slug in profile.bonusTagSlugs {
            guard let candidate = candidatesBySlug[slug] else { continue }
            guard let existingDecision = decisionsByTagID[candidate.id],
                  hasLexicalEvidence(existingDecision.features)
            else {
                continue
            }

            decisionsByTagID[candidate.id] = DeterministicTagDecision(
                tagId: existingDecision.tagId,
                score: existingDecision.score + sourceProfileBonus,
                confidence: existingDecision.confidence,
                features: Array(Set(existingDecision.features + ["source_profile_bonus:\(profile.name)"])).sorted()
            )
        }
    }

    let decisionLimit = max(1, maxTags)
    let decisions = decisionsByTagID.values
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.tagId < $1.tagId
        }
        .prefix(decisionLimit)
        .map { $0 }

    return DeterministicTagEvaluation(
        matchedSourceProfiles: matchedProfiles.map(\.name).sorted(),
        decisions: decisions
    )
}

public func generateDeterministicTagDecisions(
    candidates: [DeterministicTagCandidate],
    context: DeterministicTaggingContext,
    feedPriorsByTagId: [String: FeedTagPrior],
    attachThreshold: Double = defaultDeterministicTagAttachThreshold,
    maxTags: Int = defaultDeterministicMaxSystemTags
) -> [DeterministicTagDecision] {
    generateDeterministicTagEvaluation(
        candidates: candidates,
        context: context,
        feedPriorsByTagId: feedPriorsByTagId,
        attachThreshold: attachThreshold,
        maxTags: maxTags
    )
    .decisions
}
