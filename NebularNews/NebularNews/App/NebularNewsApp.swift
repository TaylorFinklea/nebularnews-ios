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
    @UIApplicationDelegateAdaptor(NotificationManager.self) var notificationManager

    let modelContainer: ModelContainer

    @State private var appState: AppState
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

        let appState = AppState(configuration: configuration)
        appState.containerFallbackReason = fallbackReason
        _appState = State(initialValue: appState)

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
            .overlay(alignment: .top) {
                if let reason = appState.containerFallbackReason {
                    ContainerFallbackBanner(reason: reason)
                }
            }
            .environment(appState)
            .environment(themeManager)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task {
                appState.loadKeychainCache()
                if appState.hasCompanionSession {
                    if let session = try? await appState.mobileAPI.fetchSession() {
                        appState.features = session.features
                    }
                    NotificationManager.shared.requestPermissionAndRegister()
                    // Allow time for APNs to return the token
                    try? await Task.sleep(for: .seconds(2))
                    await NotificationManager.shared.uploadTokenIfNeeded(api: appState.mobileAPI)
                }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.scheduleNextRefresh()
            }
        }
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
