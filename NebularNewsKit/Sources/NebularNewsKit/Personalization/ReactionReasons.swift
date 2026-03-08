import Foundation

public typealias ReactionValue = Int
public typealias ArticleReactionReasonCode = String

public struct ReactionReasonOption: Sendable, Hashable, Identifiable {
    public let code: ArticleReactionReasonCode
    public let label: String

    public var id: String { code }

    public init(code: ArticleReactionReasonCode, label: String) {
        self.code = code
        self.label = label
    }
}

public let upReactionReasonOptions: [ReactionReasonOption] = [
    .init(code: "up_interest_match", label: "Matches my interests"),
    .init(code: "up_source_trust", label: "Trust this source"),
    .init(code: "up_good_timing", label: "Good timing"),
    .init(code: "up_good_depth", label: "Good depth"),
    .init(code: "up_author_like", label: "Like this author")
]

public let downReactionReasonOptions: [ReactionReasonOption] = [
    .init(code: "down_off_topic", label: "Off topic for me"),
    .init(code: "down_source_distrust", label: "Don't trust this source"),
    .init(code: "down_stale", label: "Too old / stale"),
    .init(code: "down_too_shallow", label: "Too shallow"),
    .init(code: "down_avoid_author", label: "Avoid this author")
]

public let allReactionReasonOptions = upReactionReasonOptions + downReactionReasonOptions

public let reactionReasonSignalMap: [ArticleReactionReasonCode: Set<SignalName>] = [
    "up_interest_match": [.topicAffinity, .feedAffinity, .tagMatchRatio],
    "down_off_topic": [.topicAffinity, .feedAffinity, .tagMatchRatio],
    "up_source_trust": [.sourceReputation],
    "down_source_distrust": [.sourceReputation],
    "up_good_timing": [.contentFreshness],
    "down_stale": [.contentFreshness],
    "up_good_depth": [.contentDepth],
    "down_too_shallow": [.contentDepth],
    "up_author_like": [.authorAffinity],
    "down_avoid_author": [.authorAffinity]
]

public let topicReactionReasonCodes: Set<ArticleReactionReasonCode> = [
    "up_interest_match",
    "down_off_topic"
]

public let sourceReputationReactionCodes: Set<ArticleReactionReasonCode> = [
    "up_source_trust",
    "down_source_distrust"
]

public let authorReactionReasonCodes: Set<ArticleReactionReasonCode> = [
    "up_author_like",
    "down_avoid_author"
]

public let feedAffinityReactionCodes: Set<ArticleReactionReasonCode> = [
    "up_interest_match",
    "down_off_topic"
]

public func reasonOptions(for value: ReactionValue) -> [ReactionReasonOption] {
    value == 1 ? upReactionReasonOptions : downReactionReasonOptions
}

public func canonicalizeReasonCodes(for value: ReactionValue, codes: [ArticleReactionReasonCode]) -> [ArticleReactionReasonCode] {
    let selected = Set(codes)
    return reasonOptions(for: value)
        .map(\.code)
        .filter { selected.contains($0) }
}

public func targetSignals(for reasonCodes: [ArticleReactionReasonCode]) -> Set<SignalName> {
    Set(reasonCodes.flatMap { reactionReasonSignalMap[$0] ?? [] })
}

public func hasTopicReason(_ reasonCodes: [ArticleReactionReasonCode]) -> Bool {
    !topicReactionReasonCodes.isDisjoint(with: reasonCodes)
}

public func hasSourceReason(_ reasonCodes: [ArticleReactionReasonCode]) -> Bool {
    !sourceReputationReactionCodes.isDisjoint(with: reasonCodes)
}

public func hasAuthorReason(_ reasonCodes: [ArticleReactionReasonCode]) -> Bool {
    !authorReactionReasonCodes.isDisjoint(with: reasonCodes)
}

public func hasFeedAffinityReason(_ reasonCodes: [ArticleReactionReasonCode]) -> Bool {
    !feedAffinityReactionCodes.isDisjoint(with: reasonCodes)
}

public func shouldLearnFromReactionChange(previousValue: Int?, newValue: Int?) -> Bool {
    switch (previousValue, newValue) {
    case let (old?, new?) where old != new:
        return true
    case (nil, .some):
        return true
    default:
        return false
    }
}
