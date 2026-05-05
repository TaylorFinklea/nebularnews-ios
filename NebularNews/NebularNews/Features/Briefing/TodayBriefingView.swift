import SwiftUI
import SwiftData

/// Brief-only Today tab (Build 37). Renders the user's most recent
/// brief seed and surfaces brief history via the toolbar clock. All
/// chat — both freeform and "Tell me more" follow-ups from a brief
/// bullet — now lives in the dedicated Agent tab, so Today stays calm
/// and scannable. The unified-thread experiment from Build 29 was
/// reversed because chat history piled up above the brief; users now
/// get a "morning paper" surface here and a ChatGPT-style conversation
/// list one tab over.
struct TodayBriefingView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(AIAssistantCoordinator.self) private var coordinator

    @State private var isLoading = false
    @State private var errorMessage = ""

    /// View-time filter — surface ONLY brief seed rows. Anything else
    /// in the assistant thread (legacy chat from pre-Build 37) is
    /// reachable from the Agent tab's "Earlier conversation" entry.
    private var briefSeeds: [CompanionChatMessage] {
        coordinator.messages.filter { $0.kind == "brief_seed" }
    }
    @State private var dismissContext: DismissContext?
    @State private var dismissService: DismissedTopicService?
    /// Weekly Reading Insights card. nil while we haven't fetched (or
    /// the fetch failed silently — this card is optional UX and a
    /// failure shouldn't surface an error to the user). Renders above
    /// the brief when present, fresh, and not dismissed.
    @State private var weeklyInsight: CompanionWeeklyInsight?
    @State private var insightDismissed: Bool = false
    /// Local navigation target for bullet tap-to-open. Pushed onto the
    /// surrounding NavigationStack via `.navigationDestination(item:)`.
    @State private var openArticleId: String?
    /// Brief history sheet toggle (the pre-Build 35 surface, restored
    /// because chat history is now per-conversation in Agent and the
    /// daily-grouped view no longer makes sense for Today).
    @State private var showBriefHistory = false
    /// Topic brief sheet toggle.
    @State private var showTopicBrief = false
    /// Local navigation target for `nebularnews://brief/{id}` deep links.
    @State private var openBriefId: String?

    private struct DismissContext: Identifiable {
        let id = UUID()
        let signature: String
        let articleIds: [String]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if shouldShowInsight, let insight = weeklyInsight {
                    WeeklyInsightCard(insight: insight) {
                        SeenInsightStore.markSeen(insight.generatedAt)
                        withAnimation(.easeOut(duration: 0.18)) {
                            insightDismissed = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isLoading && briefSeeds.isEmpty {
                    ProgressView("Loading brief…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if briefSeeds.isEmpty {
                    emptyState
                } else {
                    briefList
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showBriefHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Brief history")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTopicBrief = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .accessibilityLabel("Topic brief")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .navigationDestination(item: $openArticleId) { articleId in
                CompanionArticleDetailView(articleId: articleId)
            }
            .navigationDestination(item: $openBriefId) { briefId in
                BriefDetailView(briefId: briefId)
            }
        }
        .task {
            if dismissService == nil {
                dismissService = DismissedTopicService(context: modelContext)
            }
            dismissService?.cleanup()
            await loadThread()
            await refreshIfStale()
            await loadWeeklyInsight()
        }
        .sheet(item: $dismissContext) { ctx in
            DismissDurationSheet(
                signature: ctx.signature,
                sourceArticleIds: ctx.articleIds
            ) { duration, allowResurface in
                dismissService?.add(
                    signature: ctx.signature,
                    sourceArticleIds: ctx.articleIds,
                    durationDays: duration,
                    allowResurfaceOnDevelopments: allowResurface
                )
            }
        }
        .sheet(isPresented: $showBriefHistory) {
            BriefHistoryView()
        }
        .sheet(isPresented: $showTopicBrief) {
            TopicBriefSheet { newBriefId in
                openBriefId = newBriefId
            }
        }
        // Brief deep-link parity with CompanionTodayView. APNs taps and
        // widget URLs route through DeepLinkRouter.pendingBriefId; we
        // observe and clear it so the push doesn't fire twice if both
        // Today views happen to be in the hierarchy.
        .onChange(of: deepLinkRouter.pendingBriefId) { _, newValue in
            if let id = newValue {
                openBriefId = id
                deepLinkRouter.clearPendingBrief()
            }
        }
        .onAppear {
            if let id = deepLinkRouter.pendingBriefId {
                openBriefId = id
                deepLinkRouter.clearPendingBrief()
            }
        }
    }

    // MARK: - Weekly Insight

    /// Show the insight card when we have one, the user hasn't tapped
    /// dismiss this session, hasn't dismissed this generation in any
    /// prior session (SeenInsightStore), and the snapshot is fresh
    /// enough that resurfacing it makes sense (<= 7 days old).
    private var shouldShowInsight: Bool {
        guard let insight = weeklyInsight else { return false }
        if insightDismissed { return false }
        if SeenInsightStore.contains(insight.generatedAt) { return false }
        let ageSec = Date().timeIntervalSince1970 - Double(insight.generatedAt) / 1000.0
        return ageSec >= 0 && ageSec <= 7 * 24 * 3600
    }

    /// Fire-and-forget weekly insight load. Failures are silent — the
    /// card is supplementary; an error here shouldn't surface alongside
    /// the brief's own error UI.
    private func loadWeeklyInsight() async {
        guard weeklyInsight == nil else { return }
        if let fetched = try? await appState.supabase.fetchWeeklyInsight() {
            weeklyInsight = fetched
        }
    }

    // MARK: - Loading

    /// 12 hours in milliseconds. Briefs older than this auto-refresh on
    /// Today tab open so the user never sees a stale seed.
    private static let staleBriefThresholdMs: Int = 12 * 60 * 60 * 1000

    private func loadThread() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Coordinator owns the messages + thread id and is shared with
        // the floating overlay. Its loadCurrentThread fetches
        // /api/chat/assistant (which the server pre-seeds with the
        // latest brief), populates coordinator.messages, and stores
        // the threadId so subsequent sendMessage writes line up.
        await coordinator.loadCurrentThread()
        errorMessage = ""
    }

    /// Called once per view appearance. If the seeded brief is older than
    /// the staleness threshold, regenerates in the background and re-loads
    /// the thread. Idempotent — running the same check twice during one
    /// open is harmless because regenerateBrief() blocks on the same
    /// request the cron would otherwise issue.
    private func refreshIfStale() async {
        guard !isLoading else { return }
        let seed = briefSeeds.first
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        // Parse generated_at out of the seed JSON; missing seed counts as
        // "stale" so first-time users automatically get a fresh brief.
        let generatedAt: Int? = {
            guard let seed, let brief = SeededBrief.parse(content: seed.content) else { return nil }
            return brief.generatedAt
        }()

        let stale: Bool
        if let generatedAt {
            stale = nowMs - generatedAt > Self.staleBriefThresholdMs
        } else {
            stale = true
        }
        guard stale else { return }
        await refresh()
    }

    private func refresh() async {
        // Trigger a fresh brief generation, then reload the thread so the
        // newly-seeded message replaces the old one.
        let payload = dismissService?.payloadForBriefRequest()
        do {
            try await regenerateBrief(suppressedTopics: payload)
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadThread()
    }

    private func regenerateBrief(suppressedTopics: [SuppressedTopicPayload]?) async throws {
        struct GenBody: Encodable {
            let lookback_hours: Int
            let depth: String?
            let suppressed_topics: [SuppressedTopicPayload]?
        }
        // Best-effort settings load — depth is optional server-side, so a
        // failure here just falls through to the "summary" default rather
        // than blocking the manual refresh.
        let depth = (try? await appState.supabase.fetchSettings())?.newsBriefConfig.depth
        let _: BriefGenerateResponseEnvelope = try await APIClient.shared.request(
            method: "POST",
            path: "api/brief/generate",
            body: GenBody(lookback_hours: 12, depth: depth, suppressed_topics: suppressedTopics)
        )
    }

    /// Opaque envelope — we don't render the response, just need to await it.
    private struct BriefGenerateResponseEnvelope: Decodable {}

    // MARK: - Brief list

    /// Brief-only List. Each brief seed renders as a Section (header +
    /// bullet rows with native swipeActions for Like / Dismiss /
    /// Dislike). Chat lives in the Agent tab now — no input, no
    /// streaming bubble, no suggested-questions row on this surface.
    @ViewBuilder
    private var briefList: some View {
        List {
            ForEach(briefSeeds) { msg in
                if let brief = SeededBrief.parse(content: msg.content) {
                    briefSection(brief: brief, anchorId: msg.id)
                }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    @ViewBuilder
    private func briefSection(brief: SeededBrief, anchorId: String) -> some View {
        Section {
            ForEach(brief.bullets) { bullet in
                BriefBulletCard(bullet: bullet, onAction: handleBulletAction)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            handleBulletAction(.reactUp(articleIds: bullet.sources.map(\.articleId)))
                        } label: {
                            Label("Like", systemImage: "hand.thumbsup.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            handleBulletAction(.dismiss(
                                signature: BriefBulletCard.signature(for: bullet),
                                articleIds: bullet.sources.map(\.articleId)
                            ))
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                        .tint(.red)
                        Button {
                            handleBulletAction(.reactDown(articleIds: bullet.sources.map(\.articleId)))
                        } label: {
                            Label("Dislike", systemImage: "hand.thumbsdown.fill")
                        }
                        .tint(.orange)
                    }
            }
        } header: {
            BriefSectionHeader(brief: brief)
                .id(anchorId)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No brief yet")
                .font(.headline)
            Text("Pull to generate a brief from the last 12 hours, or set up morning/evening scheduled briefs in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Generate now") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bullet actions

    private func handleBulletAction(_ action: BriefBulletAction) {
        switch action {
        case .save(let articleIds):
            Task { await execSave(articleIds: articleIds) }
        case .reactUp(let articleIds):
            Task { await execReact(articleIds: articleIds, value: 1) }
        case .reactDown(let articleIds):
            Task { await execReact(articleIds: articleIds, value: -1) }
        case .dismiss(let signature, let articleIds):
            dismissContext = DismissContext(signature: signature, articleIds: articleIds)
        case .tellMeMore(let prompt, let articleId):
            // Switch to the Agent tab and queue a fresh conversation
            // pinned to the bullet's primary article. The Agent root
            // view picks up `pendingAgentConversation`, creates the
            // conversation, auto-sends the prompt, and clears the flag.
            appState.pendingAgentConversation = AppState.PendingAgentConversation(
                articleId: articleId,
                articleTitle: nil,
                prompt: "Tell me more about: \(prompt)"
            )
            appState.pendingTabSwitch = "agent"
        case .openArticle(let articleId):
            // Push directly via the NavigationStack-bound state. Going
            // through DeepLinkRouter would no-op here because the legacy
            // CompanionTodayView is what observes pendingArticleId.
            openArticleId = articleId
        }
    }

    // POST /chat/exec-tool with a typed body. Two helpers (save, react) so
    // we don't need a generic [String: Any] container — args are statically
    // known per action and the server validates the tool name anyway.

    private struct SaveBody: Encodable {
        let tool: String = "save_articles"
        let args: Args
        struct Args: Encodable { let article_ids: [String] }
    }

    private struct ReactBody: Encodable {
        let tool: String = "react_to_articles"
        let args: Args
        struct Args: Encodable { let article_ids: [String]; let value: Int }
    }

    /// Tool result envelope. The undo spec is intentionally generic over
    /// the args: undo_save_articles and undo_react_to_articles both take
    /// `{ article_ids: [String] }`, so a single decoder shape suffices.
    ///
    /// The Swift property uses camelCase because APIClient's decoder applies
    /// `convertFromSnakeCase` — incoming `article_ids` is converted to
    /// `articleIds` before key matching. The undo blob re-encode in
    /// `appendToolChip` runs `convertToSnakeCase` so the server's undo
    /// handler still gets `article_ids`.
    private struct ExecToolResult: Decodable {
        let summary: String
        let succeeded: Bool
        let undo: UndoSpec?

        struct UndoSpec: Decodable {
            let tool: String
            let args: ArticleIdsArgs
        }

        struct ArticleIdsArgs: Codable {
            let articleIds: [String]
        }
    }

    private func execSave(articleIds: [String]) async {
        let body = SaveBody(args: .init(article_ids: articleIds))
        await postExecTool(label: "Save", body: body)
    }

    private func execReact(articleIds: [String], value: Int) async {
        let body = ReactBody(args: .init(article_ids: articleIds, value: value))
        await postExecTool(label: value > 0 ? "Like" : "Dislike", body: body)
    }

    /// Posts an exec-tool body, decodes the result, appends a chip into the
    /// thread for visual confirmation. `label` is only used for the error
    /// message when something goes wrong — succeess summaries come from the
    /// server.
    private func postExecTool<B: Encodable>(label: String, body: B) async {
        do {
            let result: ExecToolResult = try await APIClient.shared.request(
                method: "POST",
                path: "api/chat/exec-tool",
                body: body
            )
            appendToolChip(name: label, summary: result.summary, succeeded: result.succeeded, undo: result.undo)
        } catch {
            errorMessage = "Could not \(label.lowercased()): \(error.localizedDescription)"
        }
    }

    /// Appends a one-off tool_result message into the local thread cache so
    /// the user sees the chip without a thread reload. Server already wrote
    /// the actual mutation — the message here is purely UI feedback.
    private func appendToolChip(name: String, summary: String, succeeded: Bool, undo: ExecToolResult.UndoSpec?) {
        let undoBlob: String? = {
            guard let undo else { return nil }
            let snakeEncoder = JSONEncoder()
            snakeEncoder.keyEncodingStrategy = .convertToSnakeCase
            guard let data = try? snakeEncoder.encode(undo.args) else { return nil }
            return data.base64EncodedString()
        }()
        let marker = AssistantMessageParser.toolMarker(
            name: name,
            summary: summary,
            succeeded: succeeded,
            undoTool: undo?.tool,
            undoArgsB64: undoBlob
        )
        let msg = CompanionChatMessage(
            id: UUID().uuidString,
            threadId: coordinator.currentThreadId ?? "",
            role: "assistant",
            content: marker,
            tokenCount: nil,
            provider: nil,
            model: nil,
            createdAt: Int(Date().timeIntervalSince1970),
            messageKind: "tool_result"
        )
        coordinator.messages.append(msg)
    }

}
