import Foundation
import SwiftData

/// A single article fetched from an RSS feed.
///
/// Articles hold both the raw content (HTML) and AI-generated enrichments
/// (summary, score, key points). User state (read, reactions, tags) is
/// tracked directly on the model for simplicity in v1.
@Model
public final class Article: @unchecked Sendable {
    public var id: String = UUID().uuidString
    public var canonicalUrl: String?
    public var title: String?
    public var author: String?
    public var publishedAt: Date?
    public var fetchedAt: Date = Date()

    // Content
    public var contentHtml: String?
    public var excerpt: String?
    public var imageUrl: String?
    public var ogImageUrl: String?
    public var fallbackImageUrl: String?
    public var fallbackImageProvider: String?
    public var fallbackImageTheme: String?
    public var fallbackImageGeneratedAt: Date?
    public var contentHash: String?
    public var contentFetchAttemptedAt: Date?
    public var contentFetchedAt: Date?

    // AI-generated enrichments
    public var cardSummaryText: String?
    public var summaryText: String?
    public var summaryProvider: String?
    public var summaryModel: String?
    public var keyPointsJson: String?
    public var score: Int?
    public var scoreLabel: String?
    public var scoreConfidence: Double?
    public var scorePreferenceConfidence: Double?
    public var scoreWeightedAverage: Double?
    public var scoreExplanation: String?
    public var scoreStatus: String?
    public var signalScoresJson: String?
    public var aiProcessedAt: Date?
    public var personalizationVersion: Int = 0
    public var scoreAssistExplanation: String?
    public var scoreAssistProvider: String?
    public var scoreAssistModel: String?
    public var scoreAssistAdjustment: Int?
    public var scoreAssistGeneratedAt: Date?

    // User state
    public var isRead: Bool = false
    public var readAt: Date?
    public var dismissedAt: Date?
    public var readingListAddedAt: Date?
    public var reactionValue: Int?
    public var reactionReasonCodes: String?
    public var feedbackRating: Int?
    public var systemTagIdsJson: String?

    // Relationships
    public var feed: Feed?

    @Relationship(deleteRule: .nullify, inverse: \Tag.articles)
    public var tags: [Tag]? = []

    public init(canonicalUrl: String? = nil, title: String? = nil) {
        self.id = UUID().uuidString
        self.canonicalUrl = canonicalUrl
        self.title = title
        self.fetchedAt = Date()
    }

    // MARK: - Computed Helpers

    /// Best available image URL: RSS-provided imageUrl, then cached OG image.
    public var resolvedImageUrl: String? {
        imageUrl ?? ogImageUrl ?? fallbackImageUrl
    }

    /// Decoded key points from the JSON string.
    public var keyPoints: [String] {
        decodeJSONString(keyPointsJson, as: [String].self) ?? []
    }

    public var signalScores: [StoredSignalScore] {
        decodeJSONString(signalScoresJson, as: [StoredSignalScore].self) ?? []
    }

    public var systemTagIds: [String] {
        decodeJSONString(systemTagIdsJson, as: [String].self) ?? []
    }

    public var scoreStatusValue: LocalScoreStatus? {
        guard let scoreStatus else { return nil }
        return LocalScoreStatus(rawValue: scoreStatus)
    }

    public var hasReadyScore: Bool {
        scoreStatusValue == .ready && score != nil
    }

    public var displayedScore: Int? {
        guard let score else { return nil }
        guard let scoreAssistAdjustment else { return score }
        return min(5, max(1, score + scoreAssistAdjustment))
    }

    public var displayedScoreExplanation: String? {
        if let scoreAssistExplanation, !scoreAssistExplanation.isEmpty {
            return scoreAssistExplanation
        }
        return scoreExplanation
    }

    public var isLearningScore: Bool {
        scoreStatusValue == .insufficientSignal
    }

    public var isDismissed: Bool {
        dismissedAt != nil
    }

    public var isInReadingList: Bool {
        readingListAddedAt != nil
    }

    public var isUnreadQueueCandidate: Bool {
        !isRead && !isDismissed
    }

    /// Retention uses the article's own age when available, falling back to fetch time.
    public var retentionReferenceDate: Date {
        publishedAt ?? fetchedAt
    }

    public var bestAvailableContentText: String {
        (contentHtml ?? excerpt ?? "")
            .strippedHTML
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var bestAvailableContentLength: Int {
        bestAvailableContentText.count
    }

    public var preferredCardSummaryText: String? {
        let candidates = [
            normalizedSummary(cardSummaryText),
            normalizedSummary(summaryText).flatMap { Self.firstSentence(in: $0) },
            normalizedSummary(excerpt).flatMap { Self.firstSentence(in: $0) }
        ]

        return candidates.compactMap { $0 }.first
    }

    /// Human-readable score label, falling back to a default.
    public var displayScoreLabel: String {
        if let scoreLabel, !scoreLabel.isEmpty {
            return scoreLabel
        }
        if isLearningScore {
            return "Learning your preferences"
        }
        return displayedScore.map { "Score \($0)" } ?? "Unscored"
    }

    private func decodeJSONString<T: Decodable>(_ json: String?, as type: T.Type) -> T? {
        guard let json,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func markRead(at date: Date = Date()) {
        dismissedAt = nil
        isRead = true
        readAt = date
    }

    public func markUnread() {
        isRead = false
        readAt = nil
    }

    public func markDismissed(at date: Date = Date()) {
        isRead = false
        readAt = nil
        dismissedAt = date
    }

    public func clearDismissal() {
        dismissedAt = nil
    }

    public func addToReadingList(at date: Date = Date()) {
        readingListAddedAt = date
    }

    public func removeFromReadingList() {
        readingListAddedAt = nil
    }

    public func toggleReadingList(at date: Date = Date()) {
        if isInReadingList {
            removeFromReadingList()
        } else {
            addToReadingList(at: date)
        }
    }

    public func needsContentFetch(
        minimumTextLength: Int = 1_200,
        retryAfter: TimeInterval = 3 * 86_400,
        now: Date = Date()
    ) -> Bool {
        guard let canonicalUrl,
              URL(string: canonicalUrl) != nil
        else {
            return false
        }

        if contentFetchedAt != nil {
            return false
        }

        if bestAvailableContentLength >= minimumTextLength {
            return false
        }

        guard let attemptedAt = contentFetchAttemptedAt else {
            return true
        }

        return now.timeIntervalSince(attemptedAt) >= retryAfter
    }

    private func normalizedSummary(_ value: String?) -> String? {
        guard let rawValue = value else {
            return nil
        }

        let cleaned = rawValue
            .strippedHTML
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty
        else {
            return nil
        }

        return cleaned
    }

    private static func firstSentence(in text: String) -> String {
        let sentencePattern = #"(?s)^.*?[.!?](?:["')\]]+)?(?=\s|$)"#
        if let range = text.range(of: sentencePattern, options: .regularExpression) {
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                return sentence
            }
        }

        return text.truncated(to: 140)
    }
}
