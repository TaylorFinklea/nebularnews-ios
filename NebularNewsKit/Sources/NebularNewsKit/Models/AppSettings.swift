import Foundation
import SwiftData

public enum AIScoreAssistMode: String, Codable, CaseIterable, Sendable {
    case algorithmicOnly = "algorithmic_only"
    case explainOnly = "explain_only"
    case hybridAdjust = "hybrid_adjust"
}

/// Singleton app configuration, synced across devices via iCloud.
///
/// AI provider API keys are NOT stored here — they live in the per-device
/// Keychain for security. This model stores non-sensitive preferences only.
@Model
public final class AppSettings: @unchecked Sendable {
    public var id: String = "singleton"

    // AI configuration
    public var defaultProvider: String = "anthropic"
    public var defaultModel: String = "claude-haiku-4-5-20251001"
    public var scoringModel: String = "claude-haiku-4-5-20251001"
    public var chatModel: String = "claude-sonnet-4-6"
    public var summaryStyle: String = "concise"
    public var useOnDeviceSummaries: Bool = true
    public var useOnDeviceTagSuggestions: Bool = true
    public var automaticExternalAIFallback: Bool = false
    public var scoreAssistModeRaw: String = AIScoreAssistMode.algorithmicOnly.rawValue

    // Feed polling
    public var pollIntervalMinutes: Int = 30
    public var maxArticlesPerFeed: Int = 50

    // Data retention
    public var retentionDays: Int = 90

    // User interest profile (used for AI scoring)
    public var userProfilePrompt: String?

    // v2: optional backend sync
    public var syncServerUrl: String?
    public var syncEnabled: Bool = false

    public var updatedAt: Date = Date()

    public init() {
        self.id = "singleton"
    }

    public var scoreAssistMode: AIScoreAssistMode {
        get { AIScoreAssistMode(rawValue: scoreAssistModeRaw) ?? .algorithmicOnly }
        set { scoreAssistModeRaw = newValue.rawValue }
    }
}
