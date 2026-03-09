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

    @State private var anthropicModels: [AnthropicModelOption] = AnthropicModelCatalog.fallbackOptions
    @State private var isLoadingAnthropicModels = false
    @State private var anthropicModelsStatus: String?

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
                    Picker("Automatic AI", selection: automaticAIModeBinding) {
                        Text("Disabled").tag(AIAutomaticMode.disabled)
                        Text("On Device").tag(AIAutomaticMode.onDevice)
                        Text("LLM (Anthropic)").tag(AIAutomaticMode.anthropicLLM)
                    }

                    if settings.automaticAIMode == .anthropicLLM {
                        apiKeyRow(
                            label: "Anthropic API Key",
                            hasKey: appState.hasAnthropicKey
                        )

                        Picker("Anthropic model", selection: anthropicModelBinding) {
                            ForEach(anthropicModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }

                        if isLoadingAnthropicModels {
                            Label("Refreshing Anthropic models…", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                        } else if let anthropicModelsStatus {
                            Text(anthropicModelsStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Score assist", selection: scoreAssistModeBinding) {
                        Text("Algorithmic only").tag(AIScoreAssistMode.algorithmicOnly)
                        Text("Explain only").tag(AIScoreAssistMode.explainOnly)
                        Text("Hybrid adjust").tag(AIScoreAssistMode.hybridAdjust)
                    }
                    .disabled(settings.automaticAIMode == .disabled)
                } header: {
                    Label("AI Features", systemImage: "brain")
                } footer: {
                    Text("Automatic AI controls summaries, key points, tag suggestions, and score assist. On Device uses Foundation Models only. LLM uses Anthropic only. Disabled turns automatic AI features off entirely.")
                }

                Section {
                    apiKeyRow(
                        label: "Anthropic API Key",
                        hasKey: appState.hasAnthropicKey
                    )

                    apiKeyRow(
                        label: "OpenAI API Key",
                        hasKey: appState.hasOpenAIKey
                    )
                } header: {
                    Label("External AI Keys", systemImage: "key")
                } footer: {
                    Text("API keys stay in your device Keychain. Anthropic powers automatic LLM mode. OpenAI remains available only for explicit regenerate actions from an article.")
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
            await refreshAnthropicModelsIfNeeded()
#if DEBUG
            refreshDebugMetrics()
#endif
        }
        .task(id: anthropicModelLoadKey) {
            await refreshAnthropicModelsIfNeeded()
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

    private var automaticAIModeBinding: Binding<AIAutomaticMode> {
        Binding(
            get: { settings.automaticAIMode },
            set: { newValue in
                settings.automaticAIMode = newValue
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private var anthropicModelBinding: Binding<String> {
        Binding(
            get: { settings.anthropicModel },
            set: { newValue in
                settings.anthropicModel = newValue
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
    private func apiKeyRow(label: String, hasKey: Bool) -> some View {
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

    private var anthropicModelLoadKey: String {
        "\(settings.automaticAIMode.rawValue)-\(appState.hasAnthropicKey)-\(settings.anthropicModel)"
    }

    private func refreshAnthropicModelsIfNeeded() async {
        guard settings.automaticAIMode == .anthropicLLM else {
            await MainActor.run {
                anthropicModels = AnthropicModelCatalog.mergedOptions(
                    fetched: [],
                    including: settings.anthropicModel
                )
                anthropicModelsStatus = nil
                isLoadingAnthropicModels = false
            }
            return
        }

        guard let apiKey = appState.keychain.get(forKey: KeychainManager.Key.anthropicApiKey) else {
            await MainActor.run {
                anthropicModels = AnthropicModelCatalog.mergedOptions(
                    fetched: [],
                    including: settings.anthropicModel
                )
                anthropicModelsStatus = "Using the built-in Anthropic model list until an API key is available."
                isLoadingAnthropicModels = false
            }
            return
        }

        await MainActor.run {
            isLoadingAnthropicModels = true
            anthropicModelsStatus = nil
        }

        let client = AnthropicClient(apiKey: apiKey)

        do {
            let fetched = try await client.listModels()
            let merged = AnthropicModelCatalog.mergedOptions(
                fetched: fetched,
                including: settings.anthropicModel
            )
            await MainActor.run {
                anthropicModels = merged
                anthropicModelsStatus = fetched.isEmpty ? "Anthropic returned no models, so the built-in list is shown." : "Live list loaded from Anthropic."
                isLoadingAnthropicModels = false
            }
        } catch {
            await MainActor.run {
                anthropicModels = AnthropicModelCatalog.mergedOptions(
                    fetched: [],
                    including: settings.anthropicModel
                )
                anthropicModelsStatus = "Using the built-in Anthropic model list. \(error.localizedDescription)"
                isLoadingAnthropicModels = false
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
