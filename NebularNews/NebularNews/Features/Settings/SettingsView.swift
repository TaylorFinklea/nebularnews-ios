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
    @State private var editingAPIKey: EditableAPIKey?
    @State private var apiKeyDraft = ""

#if DEBUG
    @State private var debugAuditSnapshot: PersonalizationAuditSnapshot?
    @State private var pendingPreparationCount: Int?
    @State private var isRefreshingDebug = false
    @State private var isRebuildingDebug = false
#endif

    private var settings: AppSettings {
        if let existing = settingsResults.first {
            if existing.normalizeStorageSettings() {
                existing.updatedAt = Date()
                try? modelContext.save()
            }
            return existing
        }
        // Create singleton on first access
        let newSettings = AppSettings()
        _ = newSettings.normalizeStorageSettings()
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
                } header: {
                    Label("Feed Polling", systemImage: "antenna.radiowaves.left.and.right")
                } footer: {
                    Text("Background refresh runs approximately every poll interval. iOS may adjust timing based on usage patterns.")
                }

                Section {
                    Stepper(
                        "Archive after: \(settings.archiveAfterDays > 0 ? settings.archiveAfterDays : settings.retentionDays) days",
                        value: archiveAfterBinding,
                        in: 7...365,
                        step: 7
                    )

                    Stepper(
                        "Delete archived after: \(settings.deleteArchivedAfterDays) days",
                        value: deleteArchivedAfterBinding,
                        in: 7...365,
                        step: 7
                    )

                    Toggle("Include archived in search", isOn: searchArchivedByDefaultBinding)
                } header: {
                    Label("Storage Policy", systemImage: "archivebox")
                } footer: {
                    Text("Older articles leave the main reading surfaces after the archive window. Archived articles are deleted later unless they are saved to Reading List.")
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
                        ) {
                            apiKeyDraft = ""
                            editingAPIKey = .anthropic
                        }

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
                    ) {
                        apiKeyDraft = ""
                        editingAPIKey = .anthropic
                    }

                    apiKeyRow(
                        label: "OpenAI API Key",
                        hasKey: appState.hasOpenAIKey
                    ) {
                        apiKeyDraft = ""
                        editingAPIKey = .openAI
                    }

                    apiKeyRow(
                        label: "Unsplash Access Key",
                        hasKey: appState.hasUnsplashKey
                    ) {
                        apiKeyDraft = ""
                        editingAPIKey = .unsplash
                    }
                } header: {
                    Label("External Service Keys", systemImage: "key")
                } footer: {
                    Text("API keys stay in your device Keychain. Anthropic powers automatic LLM mode. OpenAI remains available only for explicit regenerate actions from an article. Unsplash powers live background image search for articles missing feed or OG images.")
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
                    Toggle("Enable Developer Mode", isOn: developerModeBinding)

                    if appState.isDeveloperModeEnabled {
                        NavigationLink {
                            DeveloperJobInspectorView()
                        } label: {
                            Label("Job Inspector", systemImage: "list.bullet.rectangle")
                        }
                    }
                } header: {
                    Label("Developer Mode", systemImage: "hammer")
                } footer: {
                    Text("DEBUG-only tools for inspecting the article-processing queue and personalization state on this device.")
                }

                if appState.isDeveloperModeEnabled {
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
            if appState.isDeveloperModeEnabled {
                refreshDebugMetrics()
            }
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
        .sheet(item: $editingAPIKey) { provider in
            NavigationStack {
                Form {
                    Section {
                        SecureField(provider.placeholder, text: $apiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                    } header: {
                        Text(provider.label)
                    } footer: {
                        Text(provider.footer)
                    }

                    if appState.keychain.has(key: provider.keychainKey) {
                        Section {
                            Button("Remove Key", role: .destructive) {
                                appState.keychain.delete(forKey: provider.keychainKey)
                                apiKeyDraft = ""
                                editingAPIKey = nil
                            }
                        }
                    }
                }
                .navigationTitle(provider.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            apiKeyDraft = ""
                            editingAPIKey = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else {
                                editingAPIKey = nil
                                return
                            }
                            try? appState.keychain.set(trimmed, forKey: provider.keychainKey)
                            apiKeyDraft = ""
                            editingAPIKey = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bindings that auto-save

#if DEBUG
    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { appState.isDeveloperModeEnabled },
            set: { newValue in
                appState.isDeveloperModeEnabled = newValue
                if newValue {
                    refreshDebugMetrics()
                } else {
                    debugAuditSnapshot = nil
                    pendingPreparationCount = nil
                    isRefreshingDebug = false
                    isRebuildingDebug = false
                }
            }
        )
    }
#endif

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
                _ = settings.normalizeStorageSettings()
                settings.updatedAt = Date()
                try? modelContext.save()
                enforceArticleStoragePolicies(
                    archiveAfterDays: settings.archiveAfterDays,
                    deleteArchivedAfterDays: settings.deleteArchivedAfterDays,
                    maxArticlesPerFeed: newValue
                )
            }
        )
    }

    private var archiveAfterBinding: Binding<Int> {
        Binding(
            get: {
                let current = settings.archiveAfterDays > 0 ? settings.archiveAfterDays : settings.retentionDays
                return max(current, 1)
            },
            set: { newValue in
                settings.archiveAfterDays = newValue
                settings.retentionDays = newValue
                _ = settings.normalizeStorageSettings()
                settings.updatedAt = Date()
                try? modelContext.save()
                enforceArticleStoragePolicies(
                    archiveAfterDays: newValue,
                    deleteArchivedAfterDays: settings.deleteArchivedAfterDays,
                    maxArticlesPerFeed: settings.maxArticlesPerFeed
                )
            }
        )
    }

    private var deleteArchivedAfterBinding: Binding<Int> {
        Binding(
            get: { max(settings.deleteArchivedAfterDays, 1) },
            set: { newValue in
                settings.deleteArchivedAfterDays = newValue
                _ = settings.normalizeStorageSettings()
                settings.updatedAt = Date()
                try? modelContext.save()
                enforceArticleStoragePolicies(
                    archiveAfterDays: settings.archiveAfterDays,
                    deleteArchivedAfterDays: newValue,
                    maxArticlesPerFeed: settings.maxArticlesPerFeed
                )
            }
        )
    }

    private var searchArchivedByDefaultBinding: Binding<Bool> {
        Binding(
            get: { settings.searchArchivedByDefault },
            set: { newValue in
                settings.searchArchivedByDefault = newValue
                _ = settings.normalizeStorageSettings()
                settings.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private func enforceArticleStoragePolicies(
        archiveAfterDays: Int,
        deleteArchivedAfterDays: Int,
        maxArticlesPerFeed: Int
    ) {
        let container = modelContext.container

        Task {
            let feedRepo = LocalFeedRepository(modelContainer: container)
            let articleRepo = LocalArticleRepository(modelContainer: container)
            let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
            _ = await poller.enforceArticleStoragePolicies(
                archiveAfterDays: archiveAfterDays,
                deleteArchivedAfterDays: deleteArchivedAfterDays,
                maxArticlesPerFeed: maxArticlesPerFeed
            )
#if DEBUG
            refreshDebugMetrics()
#endif
        }
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
    private func apiKeyRow(label: String, hasKey: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Not set")
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
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
        guard appState.isDeveloperModeEnabled else { return }
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
        guard appState.isDeveloperModeEnabled else { return }
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

private enum EditableAPIKey: String, Identifiable {
    case anthropic
    case openAI
    case unsplash

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic:
            return "Anthropic API Key"
        case .openAI:
            return "OpenAI API Key"
        case .unsplash:
            return "Unsplash Access Key"
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: KeychainManager.Key.anthropicApiKey
        case .openAI: KeychainManager.Key.openaiApiKey
        case .unsplash: KeychainManager.Key.unsplashAccessKey
        }
    }

    var placeholder: String {
        switch self {
        case .unsplash:
            return "Paste your Unsplash access key"
        case .anthropic, .openAI:
            return "Paste your API key"
        }
    }

    var footer: String {
        switch self {
        case .anthropic:
            return "Used for automatic Anthropic mode and explicit regenerate actions."
        case .openAI:
            return "Used only for explicit regenerate actions from an article."
        case .unsplash:
            return "Used to search Unsplash in the background for articles that do not have a feed or OG image."
        }
    }
}
