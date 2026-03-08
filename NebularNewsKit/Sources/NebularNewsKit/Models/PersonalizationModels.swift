import Foundation
import SwiftData

@Model
public final class SignalWeight: @unchecked Sendable {
    @Attribute(.unique) public var signalName: String
    public var weight: Double
    public var sampleCount: Int
    public var updatedAt: Date

    public init(signalName: String, weight: Double, sampleCount: Int = 0, updatedAt: Date = Date()) {
        self.signalName = signalName
        self.weight = weight
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
    }
}

@Model
public final class TopicAffinity: @unchecked Sendable {
    @Attribute(.unique) public var tagNameNormalized: String
    public var affinity: Double
    public var interactionCount: Int
    public var updatedAt: Date

    public init(
        tagNameNormalized: String,
        affinity: Double,
        interactionCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.tagNameNormalized = tagNameNormalized
        self.affinity = affinity
        self.interactionCount = interactionCount
        self.updatedAt = updatedAt
    }
}

@Model
public final class AuthorAffinity: @unchecked Sendable {
    @Attribute(.unique) public var authorNormalized: String
    public var affinity: Double
    public var interactionCount: Int
    public var updatedAt: Date

    public init(
        authorNormalized: String,
        affinity: Double,
        interactionCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.authorNormalized = authorNormalized
        self.affinity = affinity
        self.interactionCount = interactionCount
        self.updatedAt = updatedAt
    }
}

@Model
public final class FeedAffinity: @unchecked Sendable {
    @Attribute(.unique) public var feedKey: String
    public var affinity: Double
    public var interactionCount: Int
    public var updatedAt: Date

    public init(
        feedKey: String,
        affinity: Double,
        interactionCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.feedKey = feedKey
        self.affinity = affinity
        self.interactionCount = interactionCount
        self.updatedAt = updatedAt
    }
}

@Model
public final class ArticleTagSuggestion: @unchecked Sendable {
    public var id: String
    public var articleId: String
    @Attribute(.unique) public var articleSuggestionKey: String
    public var name: String
    public var nameNormalized: String
    public var confidence: Double?
    public var sourceProvider: String?
    public var sourceModel: String?
    public var dismissedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        articleId: String,
        name: String,
        confidence: Double? = nil,
        sourceProvider: String? = nil,
        sourceModel: String? = nil,
        dismissedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let normalizedName = ArticleTagSuggestion.normalizeName(name)
        self.id = id
        self.articleId = articleId
        self.name = name
        self.nameNormalized = normalizedName
        self.articleSuggestionKey = ArticleTagSuggestion.makeKey(articleId: articleId, normalizedName: normalizedName)
        self.confidence = confidence
        self.sourceProvider = sourceProvider
        self.sourceModel = sourceModel
        self.dismissedAt = dismissedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func normalizeName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    public static func makeKey(articleId: String, normalizedName: String) -> String {
        "\(articleId)::\(normalizedName)"
    }
}
