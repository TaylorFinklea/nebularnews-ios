import Foundation
import SwiftData

public enum ArticleProcessingStage: String, Codable, CaseIterable, Sendable {
    case scoreAndTag = "score_and_tag"
    case fetchContent = "fetch_content"
    case generateSummary = "generate_summary"
    case resolveImage = "resolve_image"
}

public enum ArticleProcessingJobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case done
    case failed
    case skipped
}

public let currentSummaryPreparationRevision = 1
public let currentImagePreparationRevision = 1

@Model
public final class ArticleProcessingJob: @unchecked Sendable {
    @Attribute(.unique) public var key: String
    public var id: String
    public var articleID: String
    public var stageRaw: String
    public var statusRaw: String
    public var priority: Int
    public var attemptCount: Int
    public var availableAt: Date
    public var inputRevision: Int
    public var lastError: String?
    public var updatedAt: Date

    public init(
        articleID: String,
        stage: ArticleProcessingStage,
        status: ArticleProcessingJobStatus = .queued,
        priority: Int,
        attemptCount: Int = 0,
        availableAt: Date = Date(),
        inputRevision: Int,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        let key = Self.makeKey(articleID: articleID, stage: stage)
        self.key = key
        self.id = key
        self.articleID = articleID
        self.stageRaw = stage.rawValue
        self.statusRaw = status.rawValue
        self.priority = priority
        self.attemptCount = attemptCount
        self.availableAt = availableAt
        self.inputRevision = inputRevision
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public var stage: ArticleProcessingStage {
        get { ArticleProcessingStage(rawValue: stageRaw) ?? .scoreAndTag }
        set { stageRaw = newValue.rawValue }
    }

    public var status: ArticleProcessingJobStatus {
        get { ArticleProcessingJobStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    public static func makeKey(articleID: String, stage: ArticleProcessingStage) -> String {
        "\(articleID)::\(stage.rawValue)"
    }
}

@Model
public final class TodaySnapshot: @unchecked Sendable {
    public var id: String
    public var generatedAt: Date
    public var heroArticleID: String?
    public var upNextArticleIDsJson: String?
    public var unreadCount: Int
    public var newTodayCount: Int
    public var highFitCount: Int
    public var readyArticleCount: Int
    public var sourceWatermark: Date

    public init(
        id: String = "singleton",
        generatedAt: Date = .distantPast,
        heroArticleID: String? = nil,
        upNextArticleIDsJson: String? = nil,
        unreadCount: Int = 0,
        newTodayCount: Int = 0,
        highFitCount: Int = 0,
        readyArticleCount: Int = 0,
        sourceWatermark: Date = .distantPast
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.heroArticleID = heroArticleID
        self.upNextArticleIDsJson = upNextArticleIDsJson
        self.unreadCount = unreadCount
        self.newTodayCount = newTodayCount
        self.highFitCount = highFitCount
        self.readyArticleCount = readyArticleCount
        self.sourceWatermark = sourceWatermark
    }

    public var upNextArticleIDs: [String] {
        guard let upNextArticleIDsJson,
              let data = upNextArticleIDsJson.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    public func updateUpNextArticleIDs(_ ids: [String]) {
        upNextArticleIDsJson = String(data: (try? JSONEncoder().encode(ids)) ?? Data("[]".utf8), encoding: .utf8)
    }
}
