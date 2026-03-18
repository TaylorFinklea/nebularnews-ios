import SwiftUI
import SwiftData
import os
import NebularNewsKit

#if DEBUG
private let personalizationReprocessLaunchArgument = "-reprocess-personalization"
#endif

private let appLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
    category: "App"
)

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
            appLogger.fault("Primary ModelContainer failed, falling back to in-memory: \(error.localizedDescription, privacy: .public)")
            modelContainer = try! makeInMemoryModelContainer()
        }

        _appState = State(initialValue: AppState(configuration: configuration))

        // Register background feed refresh task
        BackgroundTaskManager.register(modelContainer: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    if appState.isStandaloneMode && appState.isPreparingFirstBriefing {
                        FirstBriefingPreparationView()
                    } else {
                        MainTabView()
                    }
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .environment(themeManager)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task(id: appState.mode) {
                guard appState.isStandaloneMode else {
                    await ProcessingQueueSupervisor.shared.deactivate()
                    return
                }
                let settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
                let service = LocalStandalonePersonalizationService(
                    modelContainer: modelContainer,
                    keychainService: appState.configuration.keychainService
                )
                let syncService = StandaloneStateSyncService(modelContainer: modelContainer)
                await service.bootstrap()
                _ = await settingsRepo.getOrCreate()
                await syncService.bootstrap()
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains(personalizationReprocessLaunchArgument) {
                    _ = await service.reprocessAllStaleArticles(batchSize: 200)
                }
#endif
                WarmStartCoordinator.schedule(
                    modelContainer: modelContainer,
                    keychainService: appState.configuration.keychainService
                )
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                if appState.isStandaloneMode {
                    Task {
                        await ProcessingQueueSupervisor.shared.deactivate()
                    }
                    BackgroundTaskManager.scheduleNextRefresh()
                    BackgroundTaskManager.scheduleNextProcessing()
                }
            case .active:
                if appState.isStandaloneMode {
                    Task {
                        let syncService = StandaloneStateSyncService(modelContainer: modelContainer)
                        await syncService.bootstrap()
                        await ProcessingQueueSupervisor.shared.activate(
                            modelContainer: modelContainer,
                            keychainService: appState.configuration.keychainService
                        )
                    }
                }
            default:
                break
            }
        }
    }
}
