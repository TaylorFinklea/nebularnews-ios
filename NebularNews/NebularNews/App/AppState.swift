import Foundation
import Observation
import NebularNewsKit

@MainActor
@Observable
final class AppState {
    enum Mode: String {
        case companion
        case standalone
    }

    private enum DefaultsKey {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let appMode = "appMode"
    }

    let configuration: AppConfiguration
    let keychain: KeychainManager
    let mobileAPI: MobileAPIClient
    let mobileOAuthCoordinator: MobileOAuthCoordinator

    init(configuration: AppConfiguration? = nil) {
        let resolvedConfiguration = configuration ?? .shared
        self.configuration = resolvedConfiguration
        self.keychain = KeychainManager(service: resolvedConfiguration.keychainService)
        self.mobileAPI = MobileAPIClient(configuration: resolvedConfiguration, keychain: keychain)
        self.mobileOAuthCoordinator = MobileOAuthCoordinator(configuration: resolvedConfiguration)
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.hasCompletedOnboarding) }
    }

    var mode: Mode {
        get {
            let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.appMode)
            return rawValue.flatMap(Mode.init(rawValue:)) ?? .standalone
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.appMode) }
    }

    var isCompanionMode: Bool { mode == .companion }
    var isStandaloneMode: Bool { mode == .standalone }

    var hasAnthropicKey: Bool {
        keychain.has(key: KeychainManager.Key.anthropicApiKey)
    }

    var hasOpenAIKey: Bool {
        keychain.has(key: KeychainManager.Key.openaiApiKey)
    }

    var hasAnyAIKey: Bool {
        hasAnthropicKey || hasOpenAIKey
    }

    var companionServerURL: URL? {
        guard let rawValue = keychain.get(forKey: KeychainManager.Key.syncServerUrl) else { return nil }
        return URL(string: rawValue)
    }

    var hasCompanionSession: Bool {
        keychain.has(key: KeychainManager.Key.syncAccessToken) &&
            keychain.has(key: KeychainManager.Key.syncRefreshToken) &&
            companionServerURL != nil
    }

    func saveStandaloneApiKey(provider: String, key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let keychainKey = provider == "anthropic"
            ? KeychainManager.Key.anthropicApiKey
            : KeychainManager.Key.openaiApiKey
        try keychain.set(trimmed, forKey: keychainKey)
    }

    func completeStandaloneOnboarding() {
        mode = .standalone
        hasCompletedOnboarding = true
    }

    func completeCompanionOnboarding(serverURL: URL, accessToken: String, refreshToken: String) throws {
        mode = .companion
        try keychain.set(serverURL.absoluteString, forKey: KeychainManager.Key.syncServerUrl)
        try keychain.set(accessToken, forKey: KeychainManager.Key.syncAccessToken)
        try keychain.set(refreshToken, forKey: KeychainManager.Key.syncRefreshToken)
        hasCompletedOnboarding = true
    }

    func disconnectCompanion() {
        keychain.delete(forKey: KeychainManager.Key.syncAccessToken)
        keychain.delete(forKey: KeychainManager.Key.syncRefreshToken)
        keychain.delete(forKey: KeychainManager.Key.syncServerUrl)
        if isCompanionMode {
            mode = .standalone
            hasCompletedOnboarding = false
        }
    }
}
