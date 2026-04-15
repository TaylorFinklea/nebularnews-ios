import Auth
import NebularNewsKit
import SwiftUI

/// User-facing profile and preferences screen.
///
/// Separates personal settings (appearance, reading, notifications, account)
/// from platform-wide admin settings which remain in ``CompanionSettingsView``.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var settings: CompanionSettingsPayload?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var userEmail: String?

    // AI Keys
    @State private var hasAnthropicKey = false
    @State private var hasOpenAIKey = false
    @State private var showAnthropicKeyEntry = false
    @State private var showOpenAIKeyEntry = false
    @State private var pendingKeyValue = ""
    @State private var mcpConfigCopied = false
    @State private var usageSummary: UsageSummaryResponse?
    @State private var newsletterAddress: String?
    @State private var addressCopied = false
    @State private var showRegenerateConfirm = false

    private static let summaryStyles = ["concise", "detailed", "bullet"]

    var body: some View {
        List {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            // MARK: - Appearance

            Section {
                @Bindable var tm = themeManager
                Picker("Theme", selection: $tm.mode) {
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

            // MARK: - Reading

            if let settings {
                Section {
                    Picker("Summary style", selection: summaryStyleBinding(settings)) {
                        ForEach(Self.summaryStyles, id: \.self) { style in
                            Text(style.capitalized).tag(style)
                        }
                    }
                } header: {
                    Label("Reading", systemImage: "book")
                } footer: {
                    Text("Controls the format of AI-generated article summaries.")
                }
            }

            // MARK: - AI Keys

            Section {
                HStack {
                    Text("Anthropic")
                    Spacer()
                    if hasAnthropicKey {
                        Text("Configured")
                            .foregroundStyle(.green)
                        Button("Remove") { removeKey(KeychainManager.Key.anthropicApiKey) }
                            .foregroundStyle(.red)
                            .buttonStyle(.borderless)
                    } else {
                        Button("Add Key") { showAnthropicKeyEntry = true }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Text("OpenAI")
                    Spacer()
                    if hasOpenAIKey {
                        Text("Configured")
                            .foregroundStyle(.green)
                        Button("Remove") { removeKey(KeychainManager.Key.openaiApiKey) }
                            .foregroundStyle(.red)
                            .buttonStyle(.borderless)
                    } else {
                        Button("Add Key") { showOpenAIKeyEntry = true }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Label("AI Keys", systemImage: "key")
            } footer: {
                Text("Your keys are stored only on this device in the secure Keychain. They are never sent to our servers — only directly to the AI provider.")
            }

            // MARK: - AI Usage

            if let usage = usageSummary {
                Section {
                    if let tier = usage.tier {
                        LabeledContent("Plan", value: tier.capitalized)
                    } else if hasAnthropicKey || hasOpenAIKey {
                        LabeledContent("Plan", value: "BYOK")
                    } else {
                        LabeledContent("Plan", value: "On-Device")
                    }

                    if usage.daily.limit > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Today")
                                Spacer()
                                Text("\(formatTokens(usage.daily.used)) / \(formatTokens(usage.daily.limit))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            ProgressView(value: min(Double(usage.daily.used), Double(usage.daily.limit)), total: Double(usage.daily.limit))
                                .tint(usage.daily.used > usage.daily.limit ? .red : .accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("This Week")
                                Spacer()
                                Text("\(formatTokens(usage.weekly.used)) / \(formatTokens(usage.weekly.limit))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            ProgressView(value: min(Double(usage.weekly.used), Double(usage.weekly.limit)), total: Double(usage.weekly.limit))
                                .tint(usage.weekly.used > usage.weekly.limit ? .red : .accentColor)
                        }
                    } else {
                        Text("No usage limits")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Label("AI Usage", systemImage: "chart.bar")
                }
            }

            // MARK: - Newsletter Inbox

            Section {
                if let address = newsletterAddress {
                    LabeledContent("Address", value: address)
                        .font(.caption)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = address
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                        #endif
                        addressCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { addressCopied = false }
                    } label: {
                        HStack {
                            Label("Copy Address", systemImage: "doc.on.doc")
                            Spacer()
                            if addressCopied {
                                Text("Copied!").font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                    Button("Regenerate Address", role: .destructive) {
                        showRegenerateConfirm = true
                    }
                } else {
                    Button {
                        Task { await enableNewsletter() }
                    } label: {
                        Label("Enable Newsletter Inbox", systemImage: "envelope.badge.shield.half.filled")
                    }
                }
            } header: {
                Label("Newsletter Inbox", systemImage: "envelope")
            } footer: {
                Text("Forward newsletters to this address. They appear alongside your RSS feeds.")
            }
            .alert("Regenerate Address?", isPresented: $showRegenerateConfirm) {
                Button("Regenerate", role: .destructive) {
                    Task { await regenerateNewsletter() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your old address will stop receiving newsletters. You'll need to update your forwarding rules.")
            }

            // MARK: - Notifications

            if let settings {
                Section {
                    Toggle("News brief", isOn: newsBriefEnabledBinding(settings))
                    if settings.newsBriefConfig.enabled {
                        HStack {
                            Text("Timezone")
                            Spacer()
                            Text(settings.newsBriefConfig.timezone)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Morning")
                            Spacer()
                            TextField("08:00", text: morningTimeBinding(settings))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                        HStack {
                            Text("Evening")
                            Spacer()
                            TextField("17:00", text: eveningTimeBinding(settings))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                        Stepper(
                            "Lookback \(settings.newsBriefConfig.lookbackHours)h",
                            value: lookbackHoursBinding(settings),
                            in: 1...48
                        )
                        Stepper(
                            "Min score \(settings.newsBriefConfig.scoreCutoff)",
                            value: scoreCutoffBinding(settings),
                            in: 0...10
                        )
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                } footer: {
                    Text("Notification digests are sent at the configured times. Use HH:mm format.")
                }
            }

            // MARK: - Account

            Section {
                if let email = userEmail {
                    LabeledContent("Email", value: email)
                }
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Version", value: "\(version) (\(build))")
                }
                Button("Sign Out", role: .destructive) {
                    Task { await appState.signOut() }
                }
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            }

            // MARK: - Integrations

            Section {
                Button {
                    let token = APIClient.shared.sessionToken ?? "<your-session-token>"
                    let baseURL = APIClient.shared.baseURL.absoluteString
                    let config = """
                    {
                      "mcpServers": {
                        "nebularnews": {
                          "url": "\(baseURL)/api/mcp",
                          "headers": {
                            "Authorization": "Bearer \(token)"
                          }
                        }
                      }
                    }
                    """
                    #if os(iOS)
                    UIPasteboard.general.string = config
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(config, forType: .string)
                    #endif
                    mcpConfigCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { mcpConfigCopied = false }
                } label: {
                    HStack {
                        Label("Copy Claude Desktop Config", systemImage: "doc.on.doc")
                        Spacer()
                        if mcpConfigCopied {
                            Text("Copied!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Label("Integrations", systemImage: "puzzlepiece.extension")
            } footer: {
                Text("Paste this JSON into your Claude Desktop settings to connect NebularNews as an MCP server. Search articles, get briefs, and ask about your news directly from Claude.")
            }

            // MARK: - AI History

            Section {
                NavigationLink {
                    AssistantHistoryView()
                } label: {
                    Label("Chat History", systemImage: "bubble.left.and.text.bubble.right")
                }
            } header: {
                Label("AI Assistant", systemImage: "sparkles")
            }

            // MARK: - Admin

            Section {
                NavigationLink {
                    AdminDashboardView()
                } label: {
                    Label("Admin", systemImage: "shield.lefthalf.filled")
                }
            }

            // MARK: - Advanced

            Section {
                NavigationLink("Advanced Settings") {
                    CompanionSettingsView()
                }
            } footer: {
                Text("Server polling, retention, and scoring configuration.")
            }
        }
        .navigationTitle("Profile")
        .overlay { if isLoading && settings == nil { ProgressView() } }
        .task {
            await loadInitialData()
        }
        .alert("Anthropic API Key", isPresented: $showAnthropicKeyEntry) {
            SecureField("sk-ant-...", text: $pendingKeyValue)
                .textContentType(.password)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Save") { saveKey(KeychainManager.Key.anthropicApiKey) }
            Button("Cancel", role: .cancel) { pendingKeyValue = "" }
        } message: {
            Text("Enter your Anthropic API key. It will be stored securely in the device Keychain.")
        }
        .alert("OpenAI API Key", isPresented: $showOpenAIKeyEntry) {
            SecureField("sk-...", text: $pendingKeyValue)
                .textContentType(.password)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Save") { saveKey(KeychainManager.Key.openaiApiKey) }
            Button("Cancel", role: .cancel) { pendingKeyValue = "" }
        } message: {
            Text("Enter your OpenAI API key. It will be stored securely in the device Keychain.")
        }
    }

    // MARK: - Data

    private func loadInitialData() async {
        isLoading = true
        errorMessage = nil

        // Load AI key status from Keychain
        refreshKeyStatus()

        // Load user email from Supabase session
        if let session = try? await appState.supabase.session() {
            userEmail = session.user.email
        }

        // Load settings + usage in parallel
        do {
            async let fetchedSettings = appState.supabase.fetchSettings()
            async let fetchedUsage = loadUsageSummary()
            async let fetchedNewsletter = loadNewsletterAddress()
            settings = try await fetchedSettings
            usageSummary = await fetchedUsage
            newsletterAddress = await fetchedNewsletter
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadNewsletterAddress() async -> String? {
        guard APIClient.shared.hasSession else { return nil }
        struct Resp: Decodable { let address: String }
        return try? await (APIClient.shared.request(path: "api/newsletters/address") as Resp).address
    }

    private func loadUsageSummary() async -> UsageSummaryResponse? {
        guard APIClient.shared.hasSession else { return nil }
        return try? await APIClient.shared.request(path: "api/usage/summary")
    }

    private func enableNewsletter() async {
        do {
            struct Resp: Decodable { let address: String }
            let resp: Resp = try await APIClient.shared.request(path: "api/newsletters/address")
            newsletterAddress = resp.address
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func regenerateNewsletter() async {
        do {
            struct Resp: Decodable { let address: String }
            let resp: Resp = try await APIClient.shared.request(method: "POST", path: "api/newsletters/address/regenerate")
            newsletterAddress = resp.address
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func save(_ mutate: (inout CompanionSettingsPayload) -> Void) {
        guard var draft = settings else { return }
        mutate(&draft)
        settings = draft
        Task {
            do {
                settings = try await appState.supabase.updateSettings(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - AI Keys

    private func refreshKeyStatus() {
        hasAnthropicKey = appState.keychain.has(key: KeychainManager.Key.anthropicApiKey)
        hasOpenAIKey = appState.keychain.has(key: KeychainManager.Key.openaiApiKey)
    }

    private func saveKey(_ key: String) {
        let value = pendingKeyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingKeyValue = ""
        guard !value.isEmpty else { return }
        do {
            try appState.keychain.set(value, forKey: key)
            refreshKeyStatus()
        } catch {
            errorMessage = "Failed to save key: \(error.localizedDescription)"
        }
    }

    private func removeKey(_ key: String) {
        appState.keychain.delete(forKey: key)
        refreshKeyStatus()
    }

    // MARK: - Bindings

    private func summaryStyleBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.summaryStyle },
            set: { val in save { $0.summaryStyle = val } }
        )
    }

    private func newsBriefEnabledBinding(_ current: CompanionSettingsPayload) -> Binding<Bool> {
        Binding(
            get: { current.newsBriefConfig.enabled },
            set: { val in save { $0.newsBriefConfig.enabled = val } }
        )
    }

    private func morningTimeBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.newsBriefConfig.morningTime },
            set: { val in save { $0.newsBriefConfig.morningTime = val } }
        )
    }

    private func eveningTimeBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.newsBriefConfig.eveningTime },
            set: { val in save { $0.newsBriefConfig.eveningTime = val } }
        )
    }

    private func lookbackHoursBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.newsBriefConfig.lookbackHours },
            set: { val in save { $0.newsBriefConfig.lookbackHours = val } }
        )
    }

    private func scoreCutoffBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.newsBriefConfig.scoreCutoff },
            set: { val in save { $0.newsBriefConfig.scoreCutoff = val } }
        )
    }
}
