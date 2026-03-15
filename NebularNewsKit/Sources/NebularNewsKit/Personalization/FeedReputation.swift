import Foundation

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

    public var normalizedScore: Double {
        guard feedbackCount > 0 else { return 0.5 }
        return max(0, min(1, (score + 1) / 2))
    }

    public var hasFeedback: Bool {
        feedbackCount > 0
    }
}

public struct FeedReputationSummary: Identifiable, Sendable, Hashable {
    public let id: String
    public let feedKey: String
    public let feedID: String?
    public let title: String
    public let feedURL: String
    public let isEnabled: Bool
    public let feedbackCount: Int
    public let weightedFeedbackCount: Double
    public let ratingSum: Double
    public let score: Double
    public let normalizedScore: Double
    public let lastFeedbackAt: Date?

    public init(
        feedKey: String,
        feedID: String?,
        title: String,
        feedURL: String,
        isEnabled: Bool,
        feedbackCount: Int,
        weightedFeedbackCount: Double,
        ratingSum: Double,
        score: Double,
        normalizedScore: Double,
        lastFeedbackAt: Date?
    ) {
        self.id = feedKey
        self.feedKey = feedKey
        self.feedID = feedID
        self.title = title
        self.feedURL = feedURL
        self.isEnabled = isEnabled
        self.feedbackCount = feedbackCount
        self.weightedFeedbackCount = weightedFeedbackCount
        self.ratingSum = ratingSum
        self.score = score
        self.normalizedScore = normalizedScore
        self.lastFeedbackAt = lastFeedbackAt
    }
}

public struct FeedReputationAccumulator: Sendable {
    public private(set) var feedbackCount: Int = 0
    public private(set) var weightedFeedbackCount: Double = 0
    public private(set) var ratingSum: Double = 0
    public private(set) var lastFeedbackAt: Date?

    public init() {}

    public mutating func add(
        reactionValue: Int?,
        serializedReasonCodes: String?,
        feedbackAt: Date?
    ) {
        guard let reactionValue else { return }
        let reasonCodes = decodedReactionReasonCodes(serializedReasonCodes)
        guard hasSourceReason(reasonCodes) else { return }

        feedbackCount += 1
        weightedFeedbackCount += sourceReputationVoteWeight
        ratingSum += Double(reactionValue) * sourceReputationVoteWeight

        if let feedbackAt {
            lastFeedbackAt = max(lastFeedbackAt ?? feedbackAt, feedbackAt)
        }
    }

    public var reputation: FeedReputation {
        computeFeedReputation(
            feedbackCount: feedbackCount,
            weightedFeedbackCount: weightedFeedbackCount,
            ratingSum: ratingSum
        )
    }
}

public func computeFeedReputation(
    feedbackCount: Int,
    weightedFeedbackCount: Double,
    ratingSum: Double,
    priorWeight: Double = sourceReputationPriorWeight
) -> FeedReputation {
    guard feedbackCount > 0 else {
        return FeedReputation(feedbackCount: 0, weightedFeedbackCount: 0, ratingSum: 0, score: 0)
    }

    return FeedReputation(
        feedbackCount: feedbackCount,
        weightedFeedbackCount: weightedFeedbackCount,
        ratingSum: ratingSum,
        score: ratingSum / (weightedFeedbackCount + priorWeight)
    )
}
