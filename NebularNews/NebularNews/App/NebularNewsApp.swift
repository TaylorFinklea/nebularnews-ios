import SwiftUI
import SwiftData
import NebularNewsKit

#if DEBUG
private let personalizationReprocessLaunchArgument = "-reprocess-personalization"
#endif

@main
struct NebularNewsApp: App {
    let modelContainer: ModelContainer

    @State private var appState: AppState
    @State private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.shared
        do {
            modelContainer = try makeModelContainer(
                cloudKitEnabled: configuration.cloudKitEnabled,
                cloudKitContainerIdentifier: configuration.cloudKitContainerIdentifier
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        _appState = State(initialValue: AppState(configuration: configuration))

        // Register background feed refresh task
        BackgroundTaskManager.register(modelContainer: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .environment(themeManager)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task(id: appState.mode) {
                guard appState.isStandaloneMode else { return }
                let settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
                let articleRepo = LocalArticleRepository(modelContainer: modelContainer)
                let service = LocalStandalonePersonalizationService(
                    modelContainer: modelContainer,
                    keychainService: appState.configuration.keychainService
                )
                await service.bootstrap()
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains(personalizationReprocessLaunchArgument) {
                    _ = await service.reprocessAllStaleArticles(batchSize: 200)
                }
#endif
                let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()
                _ = try? await articleRepo.trimExcessArticlesPerFeed(maxPerFeed: maxArticlesPerFeed)
                await runAutomaticArticlePreparation(limit: 8)
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                if appState.isStandaloneMode {
                    BackgroundTaskManager.scheduleNextRefresh()
                }
            case .active:
                // Could trigger foreground poll-if-stale here in the future
                break
            default:
                break
            }
        }
    }

    private func runAutomaticArticlePreparation(limit: Int) async {
        let preparation = ArticlePreparationService(
            modelContainer: modelContainer,
            keychainService: appState.configuration.keychainService
        )
        _ = await preparation.processPendingArticles(batchSize: limit)
    }
}
