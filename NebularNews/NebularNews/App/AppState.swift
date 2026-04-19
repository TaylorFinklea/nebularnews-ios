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

    // MARK: - AI assistant cross-view actions (M11)
    //
    // The floating AI assistant can request the app to change view state
    // (switch tab, apply filter, trigger brief generation). Those actions
    // are "posted" here as pending bindings; the relevant view observes the
    // field, applies it on next render, and calls the clear method below.

    /// Pending tab switch requested by the AI assistant.
    /// Observed by the root view; cleared after read.
    var pendingTabSwitch: String?

    /// Pending filter snapshot for the Articles tab.
    var pendingArticlesFilter: PendingArticlesFilter?

    /// Flag: the next render of CompanionTodayView should trigger brief generation.
    var pendingBriefGeneration: Bool = false

    /// Flag: the next render of CompanionArticleDetailView for this article id should open it.
    var pendingArticleOpen: String?

    struct PendingArticlesFilter: Equatable {
        var read: String?      // "unread" | "read" | "all"
        var minScore: Int?
        var sort: String?      // "score" | "fetched"
        var tag: String?
        var query: String?
    }

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
