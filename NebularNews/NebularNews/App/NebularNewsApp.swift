import SwiftUI
import SwiftData
import NebularNewsKit

@main
struct NebularNewsApp: App {
    let modelContainer: ModelContainer

    @State private var appState: AppState
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
            if appState.hasCompletedOnboarding {
                MainTabView()
                    .environment(appState)
            } else {
                OnboardingView()
                    .environment(appState)
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
}
