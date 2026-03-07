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
