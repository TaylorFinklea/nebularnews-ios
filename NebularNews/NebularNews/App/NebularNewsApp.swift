import SwiftUI
import SwiftData
import NebularNewsKit

@main
struct NebularNewsApp: App {
    let modelContainer: ModelContainer

    @State private var appState = AppState()

    init() {
        do {
            modelContainer = try makeModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
    }
}
