import Foundation
import Observation
import NebularNewsKit

@MainActor
@Observable
final class AppState {
    enum ContainerFallbackReason {
        case diskCorrupted(any Error)
    }

    private enum DefaultsKey {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
#if DEBUG
        static let isDeveloperModeEnabled = "isDeveloperModeEnabled"
#endif
    }

    private let defaults: UserDefaults
    let configuration: AppConfiguration
    let keychain: KeychainManager
    let mobileAPI: MobileAPIClient
    let mobileOAuthCoordinator: MobileOAuthCoordinator

    var containerFallbackReason: ContainerFallbackReason?
    var features: CompanionFeatureFlags?

    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: DefaultsKey.hasCompletedOnboarding)
        }
    }

#if DEBUG
    var isDeveloperModeEnabled: Bool {
        didSet {
            defaults.set(isDeveloperModeEnabled, forKey: DefaultsKey.isDeveloperModeEnabled)
        }
    }
#endif

    init(configuration: AppConfiguration? = nil, defaults: UserDefaults = .standard) {
        let resolvedConfiguration = configuration ?? .shared
        let resolvedDefaults = defaults

        self.defaults = resolvedDefaults
        self.configuration = resolvedConfiguration
        self.hasCompletedOnboarding = resolvedDefaults.bool(forKey: DefaultsKey.hasCompletedOnboarding)
#if DEBUG
        self.isDeveloperModeEnabled = resolvedDefaults.bool(forKey: DefaultsKey.isDeveloperModeEnabled)
#endif
        self.keychain = KeychainManager(service: resolvedConfiguration.keychainService)
        self.mobileAPI = MobileAPIClient(configuration: resolvedConfiguration, keychain: keychain)
        self.mobileOAuthCoordinator = MobileOAuthCoordinator(configuration: resolvedConfiguration)
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

    func completeCompanionOnboarding(serverURL: URL, accessToken: String, refreshToken: String) throws {
        try keychain.set(serverURL.absoluteString, forKey: KeychainManager.Key.syncServerUrl)
        try keychain.set(accessToken, forKey: KeychainManager.Key.syncAccessToken)
        try keychain.set(refreshToken, forKey: KeychainManager.Key.syncRefreshToken)
        hasCompletedOnboarding = true
    }

    func disconnectCompanion() {
        keychain.delete(forKey: KeychainManager.Key.syncAccessToken)
        keychain.delete(forKey: KeychainManager.Key.syncRefreshToken)
        keychain.delete(forKey: KeychainManager.Key.syncServerUrl)
        hasCompletedOnboarding = false
    }
}
