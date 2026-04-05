import SwiftUI
import SwiftData
import os
import NebularNewsKit

private let appLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
    category: "App"
)

@main
struct NebularNewsApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(NotificationManager.self) var notificationManager
    #endif

    let modelContainer: ModelContainer
    let cacheContainer: ModelContainer

    @State private var appState: AppState
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.shared
        var fallbackReason: AppState.ContainerFallbackReason?

        do {
            modelContainer = try makeModelContainer(cloudKitEnabled: false)
        } catch {
            appLogger.error("ModelContainer creation failed: \(error, privacy: .public)")
            fallbackReason = .diskCorrupted(error)
            do {
                modelContainer = try makeInMemoryModelContainer()
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }

        // Separate SwiftData container for the Supabase cache layer + offline queue
        do {
            let cacheSchema = Schema([CachedArticle.self, CachedFeed.self, PendingAction.self])
            let cacheConfig = ModelConfiguration(
                "Cache",
                schema: cacheSchema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            cacheContainer = try ModelContainer(for: cacheSchema, configurations: [cacheConfig])
        } catch {
            appLogger.error("Cache ModelContainer creation failed: \(error, privacy: .public)")
            // Fall back to in-memory cache
            do {
                let cacheSchema = Schema([CachedArticle.self, CachedFeed.self, PendingAction.self])
                let cacheConfig = ModelConfiguration(
                    schema: cacheSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                cacheContainer = try ModelContainer(for: cacheSchema, configurations: [cacheConfig])
            } catch {
                fatalError("Failed to create even an in-memory cache container: \(error)")
            }
        }

        let appState = AppState(configuration: configuration)
        appState.containerFallbackReason = fallbackReason
        appState.setupArticleCache(modelContext: cacheContainer.mainContext)
        appState.setupSyncManager(modelContext: cacheContainer.mainContext)
        _appState = State(initialValue: appState)

        BackgroundTaskManager.register(modelContainer: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !appState.hasCompletedOnboarding {
                    OnboardingView()
                } else if !appState.hasCompletedFeedSelection {
                    FeedSelectionView()
                } else {
                    MainTabView()
                }
            }
            .overlay(alignment: .top) {
                if let reason = appState.containerFallbackReason {
                    ContainerFallbackBanner(reason: reason)
                }
            }
            .environment(appState)
            .environment(deepLinkRouter)
            .environment(themeManager)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .onOpenURL { url in
                deepLinkRouter.handle(url)
            }
            .task {
                await appState.loadSession()
                if appState.hasSession {
                    if !appState.hasCompletedOnboarding {
                        appState.completeSignIn()
                    }
                    #if os(iOS)
                    NotificationManager.shared.requestPermissionAndRegister()
                    try? await Task.sleep(for: .seconds(2))
                    await NotificationManager.shared.uploadTokenIfNeeded(supabase: appState.supabase)
                    #endif
                }
            }
        }
        .modelContainer(modelContainer)
        #if os(iOS)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.scheduleNextRefresh()
            }
        }
        #endif
    }
}

private struct ContainerFallbackBanner: View {
    let reason: AppState.ContainerFallbackReason
    @State private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                Spacer()
                Button {
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var message: String {
        switch reason {
        case .diskCorrupted:
            "Running in temporary mode. Data will not persist between launches."
        }
    }
}
