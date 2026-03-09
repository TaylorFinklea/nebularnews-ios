import SwiftUI
import SwiftData
import NebularNewsKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    /// When true, shows a Done button for sheet dismissal.
    var showsDismissButton: Bool = false

    @Query private var settingsResults: [AppSettings]

#if DEBUG
    @State private var debugAuditSnapshot: PersonalizationAuditSnapshot?
    @State private var pendingPreparationCount: Int?
    @State private var isRefreshingDebug = false
    @State private var isRebuildingDebug = false
#endif

    private var settings: AppSettings {
        if let existing = settingsResults.first {
            return existing
        }
        // Create singleton on first access
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        try? modelContext.save()
        return newSettings
    }

    var body: some View {
        NebularScreen {
            List {
                Section {
                    GlassCard(cornerRadius: 24, style: .raised, tintColor: .purple) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Workspace settings")
                                .font(.title3.bold())
                            Text("Tune how Nebular looks, polls, and scores without leaving the app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Picker("Poll interval", selection: pollIntervalBinding) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }

                    Stepper(
                        "Max articles per feed: \(settings.maxArticlesPerFeed)",
                        value: maxArticlesBinding,
                        in: 10...200,
                        step: 10
                    )

                    Stepper(
                        "Retention: \(settings.retentionDays) days",
                        value: retentionBinding,
                        in: 7...365,
                        step: 7
                    )
                } header: {
                    Label("Feed Polling", systemImage: "antenna.radiowaves.left.and.right")
                } footer: {
                    Text("Background refresh runs approximately every poll interval. iOS may adjust timing based on usage patterns.")
                }

                Section {
                    Picker("Default provider", selection: providerBinding) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }

                    apiKeyRow(
                        label: "Anthropic API Key",
                        hasKey: appState.hasAnthropicKey,
                        provider: "anthropic"
                    )

                    apiKeyRow(
                        label: "OpenAI API Key",
                        hasKey: appState.hasOpenAIKey,
                        provider: "openai"
                    )
                } header: {
                    Label("AI Provider", systemImage: "brain")
                } footer: {
                    Text("API keys are stored securely in your device Keychain and never synced to iCloud. In standalone mode, keys are only used for optional summaries and key points.")
                }

                Section {
                    Toggle("Use on-device summaries", isOn: onDeviceSummariesBinding)
                    Toggle("Use on-device tag suggestions", isOn: onDeviceTagSuggestionsBinding)
                    Toggle("Allow automatic external fallback", isOn: automaticFallbackBinding)

                    Picker("Score assist", selection: scoreAssistModeBinding) {
                        Text("Algorithmic only").tag(AIScoreAssistMode.algorithmicOnly)
                        Text("Explain only").tag(AIScoreAssistMode.explainOnly)
                        Text("Hybrid adjust").tag(AIScoreAssistMode.hybridAdjust)
                    }
                } header: {
                    Label("AI Behavior", systemImage: "cpu")
                } footer: {
                    Text("On-device features use Foundation Models when supported by the current runtime. Automatic external fallback stays off by default to avoid surprise credit usage.")
                }

                Section {
                    Picker("Appearance", selection: Bindable(themeManager).mode) {
                        ForEach(ThemeManager.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "paintbrush")
                } footer: {
                    Text("System follows your device's light/dark mode setting.")
                }

                Section {
                    LabeledContent("Mode", value: appState.isCompanionMode ? "Companion" : "Standalone")
                    LabeledContent("CloudKit", value: appState.configuration.cloudKitEnabled ? "Enabled" : "Disabled")

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        LabeledContent("Version", value: "\(version) (\(build))")
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }

#if DEBUG
                Section {
                    if let snapshot = debugAuditSnapshot {
                        LabeledContent("Migration progress", value: "\(snapshot.currentVersionArticles) / \(snapshot.totalArticles)")
                        LabeledContent("Still stale", value: "\(snapshot.staleArticles)")
                        LabeledContent("Ready scores", value: "\(snapshot.totalReadyScores)")
                        LabeledContent("Recent ready", value: "\(snapshot.recentReadyScores)")
                        LabeledContent("Pending prep", value: pendingPreparationCount.map(String.init) ?? "Loading")
                        LabeledContent("Feed affinity rows", value: "\(snapshot.feedAffinityRows)")
                        LabeledContent("Topic affinity rows", value: "\(snapshot.topicAffinityRows)")
                        LabeledContent("Author affinity rows", value: "\(snapshot.authorAffinityRows)")
                        LabeledContent("Learned weights", value: "\(snapshot.signalWeightRows)")
                        LabeledContent("Over-tagged", value: "\(snapshot.overTaggedArticles)")
                    } else {
                        HStack(spacing: 12) {
                            if isRefreshingDebug || isRebuildingDebug {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Loading personalization diagnostics…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        refreshDebugMetrics()
                    } label: {
                        Label("Refresh Diagnostics", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshingDebug || isRebuildingDebug)

                    Button {
                        runDebugRebuild()
                    } label: {
                        Label("Force Rebuild History", systemImage: "hammer")
                    }
                    .disabled(isRefreshingDebug || isRebuildingDebug)
                } header: {
                    Label("Debug Personalization", systemImage: "ladybug")
                } footer: {
                    Text("Temporary on-device readout for V6 migration progress. Force rebuild replays historical reactions and dismissals for this device only.")
                }
#endif
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task {
#if DEBUG
            refreshDebugMetrics()
#endif
        }
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Bindings that auto-save

    private var pollIntervalBinding: Binding<Int> {
        Binding(
            get: { settings.pollIntervalMinutes },
            set: { newValue in
                settings.pollIntervalMinutes = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var maxArticlesBinding: Binding<Int> {
        Binding(
            get: { settings.maxArticlesPerFeed },
            set: { newValue in
                settings.maxArticlesPerFeed = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { settings.retentionDays },
            set: { newValue in
                settings.retentionDays = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { settings.defaultProvider },
            set: { newValue in
                settings.defaultProvider = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var onDeviceSummariesBinding: Binding<Bool> {
        Binding(
            get: { settings.useOnDeviceSummaries },
            set: { newValue in
                settings.useOnDeviceSummaries = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var onDeviceTagSuggestionsBinding: Binding<Bool> {
        Binding(
            get: { settings.useOnDeviceTagSuggestions },
            set: { newValue in
                settings.useOnDeviceTagSuggestions = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var automaticFallbackBinding: Binding<Bool> {
        Binding(
            get: { settings.automaticExternalAIFallback },
            set: { newValue in
                settings.automaticExternalAIFallback = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var scoreAssistModeBinding: Binding<AIScoreAssistMode> {
        Binding(
            get: { settings.scoreAssistMode },
            set: { newValue in
                settings.scoreAssistMode = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    // MARK: - API Key Row

    @ViewBuilder
    private func apiKeyRow(label: String, hasKey: Bool, provider: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if hasKey {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Not set")
                    .foregroundStyle(.tertiary)
            }
        }
    }

#if DEBUG
    private func refreshDebugMetrics() {
        guard !isRefreshingDebug else { return }
        isRefreshingDebug = true

        Task {
            let container = modelContext.container
            let personalization = LocalStandalonePersonalizationService(
                modelContainer: container,
                keychainService: appState.configuration.keychainService
            )
            let preparation = ArticlePreparationService(
                modelContainer: container,
                keychainService: appState.configuration.keychainService
            )

            let snapshot = await personalization.auditSnapshot()
            let pendingCount = await preparation.pendingPresentationCount()

            await MainActor.run {
                debugAuditSnapshot = snapshot
                pendingPreparationCount = pendingCount
                isRefreshingDebug = false
            }
        }
    }

    private func runDebugRebuild() {
        guard !isRebuildingDebug else { return }
        isRebuildingDebug = true

        Task {
            let container = modelContext.container
            let personalization = LocalStandalonePersonalizationService(
                modelContainer: container,
                keychainService: appState.configuration.keychainService
            )

            _ = await personalization.rebuildPersonalizationFromHistory(batchSize: 200, force: true)
            let snapshot = await personalization.auditSnapshot()
            let preparation = ArticlePreparationService(
                modelContainer: container,
                keychainService: appState.configuration.keychainService
            )
            let pendingCount = await preparation.pendingPresentationCount()

            await MainActor.run {
                debugAuditSnapshot = snapshot
                pendingPreparationCount = pendingCount
                isRebuildingDebug = false
                isRefreshingDebug = false
            }
        }
    }
#endif
}
