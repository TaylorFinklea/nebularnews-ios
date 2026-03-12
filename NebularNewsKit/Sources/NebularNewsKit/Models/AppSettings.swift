import Foundation
import SwiftData

public enum AIScoreAssistMode: String, Codable, CaseIterable, Sendable {
    case algorithmicOnly = "algorithmic_only"
    case explainOnly = "explain_only"
    case hybridAdjust = "hybrid_adjust"
}

public enum AIAutomaticMode: String, Codable, CaseIterable, Sendable {
    case disabled = "disabled"
    case onDevice = "on_device"
    case anthropicLLM = "anthropic_llm"
}

/// Singleton app configuration, synced across devices via iCloud.
///
/// AI provider API keys are NOT stored here — they live in the per-device
/// Keychain for security. This model stores non-sensitive preferences only.
@Model
public final class AppSettings: @unchecked Sendable {
    public var id: String = "singleton"

    // AI configuration
    public var automaticAIModeRaw: String = ""
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

    // Legacy retention setting retained for lightweight migration to archive storage.
    public var retentionDays: Int = 13
    public var archiveAfterDays: Int = 0
    public var deleteArchivedAfterDays: Int = 30
    public var searchArchivedByDefault: Bool = false
    public var syncedPreferencesUpdatedAt: Date?

    // Personalization migrations
    public var personalizationRebuildVersion: Int = 0

    // User interest profile (used for AI scoring)
    public var userProfilePrompt: String?

    // v2: optional backend sync
    public var syncServerUrl: String?
    public var syncEnabled: Bool = false

    public var updatedAt: Date = Date()

    public init() {
        self.id = "singleton"
    }

    @discardableResult
    public func normalizeStorageSettings() -> Bool {
        var didChange = false

        if archiveAfterDays <= 0 {
            archiveAfterDays = max(retentionDays, 1)
            didChange = true
        }

        if deleteArchivedAfterDays <= 0 {
            deleteArchivedAfterDays = 30
            didChange = true
        }

        if retentionDays != archiveAfterDays {
            retentionDays = archiveAfterDays
            didChange = true
        }

        return didChange
    }

    public var scoreAssistMode: AIScoreAssistMode {
        get { AIScoreAssistMode(rawValue: scoreAssistModeRaw) ?? .algorithmicOnly }
        set { scoreAssistModeRaw = newValue.rawValue }
    }

    public var automaticAIMode: AIAutomaticMode {
        get {
            if let explicit = AIAutomaticMode(rawValue: automaticAIModeRaw), !automaticAIModeRaw.isEmpty {
                return explicit
            }

            if useOnDeviceSummaries || useOnDeviceTagSuggestions {
                return .onDevice
            }

            if automaticExternalAIFallback, defaultProvider == AIGenerationProvider.anthropic.rawValue {
                return .anthropicLLM
            }

            return .disabled
        }
        set {
            automaticAIModeRaw = newValue.rawValue

            switch newValue {
            case .disabled:
                useOnDeviceSummaries = false
                useOnDeviceTagSuggestions = false
                automaticExternalAIFallback = false

            case .onDevice:
                useOnDeviceSummaries = true
                useOnDeviceTagSuggestions = true
                automaticExternalAIFallback = false

            case .anthropicLLM:
                defaultProvider = AIGenerationProvider.anthropic.rawValue
                useOnDeviceSummaries = false
                useOnDeviceTagSuggestions = false
                automaticExternalAIFallback = true
            }
        }
    }

    public var anthropicModel: String {
        get {
            AnthropicModelCatalog.resolve(preferred: modelLooksAnthropic(defaultModel) ? defaultModel : nil)
        }
        set {
            let resolved = AnthropicModelCatalog.resolve(preferred: newValue)
            defaultProvider = AIGenerationProvider.anthropic.rawValue
            defaultModel = resolved
            scoringModel = resolved
        }
    }
}

private func modelLooksAnthropic(_ value: String?) -> Bool {
    guard let value else { return false }
    return value.lowercased().contains("claude")
}
