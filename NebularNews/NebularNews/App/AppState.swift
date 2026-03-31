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
        static let hasCompletedFeedSelection = "hasCompletedFeedSelection"
#if DEBUG
        static let isDeveloperModeEnabled = "isDeveloperModeEnabled"
#endif
    }

    private let defaults: UserDefaults
    let configuration: AppConfiguration
    let keychain: KeychainManager
    let supabase: SupabaseManager

    // Keep MobileAPIClient available for a transition period so existing
    // call-sites that haven't been migrated yet can still compile.
    // Once every view is migrated, this property can be removed.
    let mobileAPI: MobileAPIClient

    var containerFallbackReason: ContainerFallbackReason?

    /// Whether the user has an active Supabase session.
    private(set) var hasSession: Bool = false

    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: DefaultsKey.hasCompletedOnboarding)
        }
    }

    var hasCompletedFeedSelection: Bool {
        didSet {
            defaults.set(hasCompletedFeedSelection, forKey: DefaultsKey.hasCompletedFeedSelection)
        }
    }

#if DEBUG
    var isDeveloperModeEnabled: Bool {
        didSet {
            defaults.set(isDeveloperModeEnabled, forKey: DefaultsKey.isDeveloperModeEnabled)
        }
    }
#endif

    // Feature flags — all enabled by default with Supabase (no server feature gating)
    var features: CompanionFeatureFlags? = CompanionFeatureFlags(
        dashboard: true,
        newsBrief: true,
        reactions: true,
        tags: true
    )

    init(configuration: AppConfiguration? = nil, defaults: UserDefaults = .standard) {
        let resolvedConfiguration = configuration ?? .shared
        let resolvedDefaults = defaults

        self.defaults = resolvedDefaults
        self.configuration = resolvedConfiguration
        self.hasCompletedOnboarding = resolvedDefaults.bool(forKey: DefaultsKey.hasCompletedOnboarding)
        self.hasCompletedFeedSelection = resolvedDefaults.bool(forKey: DefaultsKey.hasCompletedFeedSelection)
#if DEBUG
        self.isDeveloperModeEnabled = resolvedDefaults.bool(forKey: DefaultsKey.isDeveloperModeEnabled)
#endif
        self.keychain = KeychainManager(service: resolvedConfiguration.keychainService)
        self.supabase = SupabaseManager.shared
        self.mobileAPI = MobileAPIClient(configuration: resolvedConfiguration, keychain: keychain)
    }

    /// Check if the user already has an active Supabase auth session.
    func loadSession() async {
        do {
            _ = try await supabase.session()
            hasSession = true
        } catch {
            hasSession = false
        }
    }

    func completeSignIn() {
        hasSession = true
        hasCompletedOnboarding = true
    }

    func completeFeedSelection() {
        hasCompletedFeedSelection = true
    }

    func signOut() async {
        try? await supabase.signOut()
        hasSession = false
        hasCompletedOnboarding = false
        hasCompletedFeedSelection = false
    }

    // MARK: - Legacy companion session support (for backward compat during transition)

    private(set) var companionServerURL: URL?
    private(set) var hasCompanionSession: Bool = false
    let mobileOAuthCoordinator: MobileOAuthCoordinator = MobileOAuthCoordinator(configuration: .shared)

    func loadKeychainCache() {
        let raw = keychain.get(forKey: KeychainManager.Key.syncServerUrl)
        companionServerURL = raw.flatMap { URL(string: $0) }
        hasCompanionSession = keychain.has(key: KeychainManager.Key.syncAccessToken)
            && keychain.has(key: KeychainManager.Key.syncRefreshToken)
            && companionServerURL != nil
    }

    func completeCompanionOnboarding(serverURL: URL, accessToken: String, refreshToken: String) throws {
        try keychain.set(serverURL.absoluteString, forKey: KeychainManager.Key.syncServerUrl)
        try keychain.set(accessToken, forKey: KeychainManager.Key.syncAccessToken)
        try keychain.set(refreshToken, forKey: KeychainManager.Key.syncRefreshToken)
        companionServerURL = serverURL
        hasCompanionSession = true
        hasCompletedOnboarding = true
    }

    func disconnectCompanion() {
        keychain.delete(forKey: KeychainManager.Key.syncAccessToken)
        keychain.delete(forKey: KeychainManager.Key.syncRefreshToken)
        keychain.delete(forKey: KeychainManager.Key.syncServerUrl)
        companionServerURL = nil
        hasCompanionSession = false
        hasCompletedOnboarding = false
        hasCompletedFeedSelection = false
    }
}
