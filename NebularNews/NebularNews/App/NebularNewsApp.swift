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
    @State private var lastSyncBootstrapAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.shared
        var fallbackReason: AppState.ContainerFallbackReason?

        if let container = Self.makeContainerWithFallback(configuration: configuration, fallbackReason: &fallbackReason) {
            modelContainer = container
        } else {
            // Last resort: in-memory container so the app can at least launch
            do {
                modelContainer = try makeInMemoryModelContainer()
            } catch {
                // If even in-memory fails, there's a fundamental SwiftData issue
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }

        let appState = AppState(configuration: configuration)
        appState.containerFallbackReason = fallbackReason
        _appState = State(initialValue: appState)

        BackgroundTaskManager.register(modelContainer: modelContainer)
    }

    private static func makeContainerWithFallback(
        configuration: AppConfiguration,
        fallbackReason: inout AppState.ContainerFallbackReason?
    ) -> ModelContainer? {
        // Tier 1: Try with the requested CloudKit configuration
        do {
            return try makeModelContainer(
                cloudKitEnabled: configuration.cloudKitEnabled,
                cloudKitContainerIdentifier: configuration.cloudKitContainerIdentifier
            )
        } catch {
            appLogger.error("ModelContainer creation failed: \(error, privacy: .public)")

            // Tier 2: If CloudKit was enabled, retry without it
            if configuration.cloudKitEnabled {
                fallbackReason = .cloudKitUnavailable(error)
                do {
                    appLogger.notice("Retrying ModelContainer without CloudKit")
                    return try makeModelContainer(cloudKitEnabled: false)
                } catch {
                    appLogger.error("Local-only ModelContainer also failed: \(error, privacy: .public)")
                    fallbackReason = .diskCorrupted(error)
                }
            } else {
                fallbackReason = .diskCorrupted(error)
            }
        }

        return nil
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
            .overlay(alignment: .top) {
                if let reason = appState.containerFallbackReason {
                    ContainerFallbackBanner(reason: reason)
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
                lastSyncBootstrapAt = Date()
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
                        let now = Date()
                        let shouldSync = lastSyncBootstrapAt.map { now.timeIntervalSince($0) > 300 } ?? true
                        if shouldSync {
                            let syncService = StandaloneStateSyncService(modelContainer: modelContainer)
                            await syncService.bootstrap()
                            lastSyncBootstrapAt = now
                        }
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
        case .cloudKitUnavailable:
            "iCloud sync unavailable this session. Your data is stored locally."
        case .diskCorrupted:
            "Running in temporary mode. Data will not persist between launches."
        }
    }
}
