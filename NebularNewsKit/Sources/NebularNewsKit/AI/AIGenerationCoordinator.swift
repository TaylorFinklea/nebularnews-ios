import Foundation
import SwiftData

public protocol AIGenerationCoordinating: Sendable {
    func isFoundationModelsAvailable() async -> Bool
    func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget
    ) async throws -> SummaryGenerationOutput?
    func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput?
    func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput?
}

public actor AIGenerationCoordinator: AIGenerationCoordinating {
    private let settingsRepo: LocalSettingsRepository
    private let keychain: KeychainManager
    private let foundationModelsEngine: any ArticleGenerationEngine
    private let anthropicFactory: @Sendable (String, String) -> any ArticleGenerationEngine
    private let openAIFactory: @Sendable (String, String) -> any ArticleGenerationEngine

    public init(
        modelContainer: ModelContainer,
        keychainService: String = "com.nebularnews.ios",
        foundationModelsEngine: (any ArticleGenerationEngine)? = nil,
        anthropicFactory: (@Sendable (String, String) -> any ArticleGenerationEngine)? = nil,
        openAIFactory: (@Sendable (String, String) -> any ArticleGenerationEngine)? = nil
    ) {
        self.settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
        self.keychain = KeychainManager(service: keychainService)
        self.foundationModelsEngine = foundationModelsEngine ?? FoundationModelsEngine()
        self.anthropicFactory = anthropicFactory ?? { apiKey, modelIdentifier in
            AnthropicGenerationEngine(apiKey: apiKey, modelIdentifier: modelIdentifier)
        }
        self.openAIFactory = openAIFactory ?? { apiKey, modelIdentifier in
            OpenAIGenerationEngine(apiKey: apiKey, modelIdentifier: modelIdentifier)
        }
    }

    public func isFoundationModelsAvailable() async -> Bool {
        await foundationModelsEngine.isAvailable()
    }

    public func generateSummary(
        snapshot: ArticleSnapshot,
        summaryStyle: String,
        target: AIExplicitGenerationTarget = .automatic
    ) async throws -> SummaryGenerationOutput? {
        let settings = await settingsRepo.getOrCreate()

        switch target {
        case .automatic:
            if settings.useOnDeviceSummaries,
               await foundationModelsEngine.isAvailable() {
                return try await foundationModelsEngine.generateSummary(
                    snapshot: snapshot,
                    summaryStyle: summaryStyle
                )
            }

            guard settings.automaticExternalAIFallback,
                  let engine = makeDefaultExternalEngine(
                    provider: externalDefaultProvider(from: settings),
                    purpose: .summary,
                    settings: settings
                  )
            else {
                return nil
            }

            return try await engine.generateSummary(snapshot: snapshot, summaryStyle: summaryStyle)

        case .anthropic:
            guard let engine = makeExternalEngine(provider: .anthropic, purpose: .summary, settings: settings) else {
                return nil
            }
            return try await engine.generateSummary(snapshot: snapshot, summaryStyle: summaryStyle)

        case .openAI:
            guard let engine = makeExternalEngine(provider: .openAI, purpose: .summary, settings: settings) else {
                return nil
            }
            return try await engine.generateSummary(snapshot: snapshot, summaryStyle: summaryStyle)
        }
    }

    public func generateTagSuggestions(
        input: TagSuggestionInput
    ) async throws -> TagSuggestionOutput? {
        let settings = await settingsRepo.getOrCreate()

        if settings.useOnDeviceTagSuggestions,
           await foundationModelsEngine.isAvailable() {
            return try await foundationModelsEngine.generateTagSuggestions(input: input)
        }

        guard settings.automaticExternalAIFallback,
              let engine = makeDefaultExternalEngine(
                provider: externalDefaultProvider(from: settings),
                purpose: .tagSuggestion,
                settings: settings
              )
        else {
            return nil
        }

        return try await engine.generateTagSuggestions(input: input)
    }

    public func generateScoreAssist(
        input: ScoreAssistInput
    ) async throws -> ScoreAssistOutput? {
        let settings = await settingsRepo.getOrCreate()
        guard settings.scoreAssistMode != .algorithmicOnly else {
            return nil
        }

        if await foundationModelsEngine.isAvailable() {
            return try await foundationModelsEngine.generateScoreAssist(input: input)
        }

        guard settings.automaticExternalAIFallback,
              let engine = makeDefaultExternalEngine(
                provider: externalDefaultProvider(from: settings),
                purpose: .scoreAssist,
                settings: settings
              )
        else {
            return nil
        }

        return try await engine.generateScoreAssist(input: input)
    }

    private func makeDefaultExternalEngine(
        provider: AIGenerationProvider,
        purpose: ExternalGenerationPurpose,
        settings: AppSettings
    ) -> (any ArticleGenerationEngine)? {
        makeExternalEngine(provider: provider, purpose: purpose, settings: settings)
    }

    private func makeExternalEngine(
        provider: AIGenerationProvider,
        purpose: ExternalGenerationPurpose,
        settings: AppSettings
    ) -> (any ArticleGenerationEngine)? {
        switch provider {
        case .anthropic:
            guard let apiKey = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) else {
                return nil
            }
            return anthropicFactory(apiKey, modelIdentifier(for: .anthropic, purpose: purpose, settings: settings))

        case .openAI:
            guard let apiKey = keychain.get(forKey: KeychainManager.Key.openaiApiKey) else {
                return nil
            }
            return openAIFactory(apiKey, modelIdentifier(for: .openAI, purpose: purpose, settings: settings))

        case .foundationModels:
            return nil
        }
    }

    private func externalDefaultProvider(from settings: AppSettings) -> AIGenerationProvider {
        settings.defaultProvider == AIGenerationProvider.openAI.rawValue ? .openAI : .anthropic
    }

    private func modelIdentifier(
        for provider: AIGenerationProvider,
        purpose: ExternalGenerationPurpose,
        settings: AppSettings
    ) -> String {
        switch (provider, purpose) {
        case (.anthropic, .summary), (.anthropic, .tagSuggestion):
            return resolvedAnthropicModel(
                preferred: settings.defaultProvider == AIGenerationProvider.anthropic.rawValue ? settings.defaultModel : nil
            )
        case (.openAI, .summary), (.openAI, .tagSuggestion):
            return resolvedOpenAIModel(
                preferred: settings.defaultProvider == AIGenerationProvider.openAI.rawValue ? settings.defaultModel : nil
            )
        case (.anthropic, .scoreAssist):
            return resolvedAnthropicModel(preferred: settings.scoringModel)
        case (.openAI, .scoreAssist):
            return resolvedOpenAIModel(preferred: settings.scoringModel)
        default:
            return resolvedAnthropicModel(preferred: nil)
        }
    }

    private func resolvedAnthropicModel(preferred: String?) -> String {
        guard let preferred,
              modelLooksAnthropic(preferred)
        else {
            return "claude-haiku-4-5-20251001"
        }
        return preferred
    }

    private func resolvedOpenAIModel(preferred: String?) -> String {
        guard let preferred,
              modelLooksOpenAI(preferred)
        else {
            return "gpt-4o-mini"
        }
        return preferred
    }
}

private enum ExternalGenerationPurpose {
    case summary
    case tagSuggestion
    case scoreAssist
}

private func modelLooksAnthropic(_ value: String) -> Bool {
    value.lowercased().contains("claude")
}

private func modelLooksOpenAI(_ value: String) -> Bool {
    let normalized = value.lowercased()
    return normalized.hasPrefix("gpt")
        || normalized.hasPrefix("o1")
        || normalized.hasPrefix("o3")
        || normalized.hasPrefix("o4")
}
