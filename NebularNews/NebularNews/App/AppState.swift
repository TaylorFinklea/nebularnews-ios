import Foundation
import Observation
import SwiftData
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

    /// SwiftData local cache for instant loads and offline reading.
    private(set) var articleCache: ArticleCache?

    /// Offline action queue and network connectivity monitor.
    private(set) var syncManager: SyncManager?

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
    }

    /// Initialize the SwiftData article cache. Call once after the model container is available.
    func setupArticleCache(modelContext: ModelContext) {
        guard articleCache == nil else { return }
        articleCache = ArticleCache(modelContext: modelContext)
    }

    /// Initialize the offline sync manager. Call once after the model container is available.
    func setupSyncManager(modelContext: ModelContext) {
        guard syncManager == nil else { return }
        let manager = SyncManager(modelContext: modelContext, supabase: supabase)
        manager.appState = self
        syncManager = manager
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
}
