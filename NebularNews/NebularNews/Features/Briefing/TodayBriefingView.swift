import SwiftUI
import SwiftData

/// Chat-first Today tab. Renders the user's shared assistant thread —
/// the same thread the floating AI overlay shows from elsewhere in the
/// app, so Today and the overlay are two views onto one conversation.
/// The brief seed lands as a structured assistant message inside that
/// thread (server-side `ensureTodayBriefSeed` makes sure it's there);
/// follow-ups, "Tell me more" replies, and freeform chat all sit
/// alongside it instead of branching off into separate threads.
struct TodayBriefingView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(AIAssistantCoordinator.self) private var coordinator

    @State private var thread: CompanionChatThread?
    @State private var messages: [CompanionChatMessage] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var inputText = ""
    @State private var dismissContext: DismissContext?
    @State private var dismissService: DismissedTopicService?
    /// Weekly Reading Insights card. nil while we haven't fetched (or
    /// the fetch failed silently — this card is optional UX and a
    /// failure shouldn't surface an error to the user). Renders above
    /// the chat thread when present, fresh, and not dismissed.
    @State private var weeklyInsight: CompanionWeeklyInsight?
    @State private var insightDismissed: Bool = false
    /// Local navigation target for bullet tap-to-open. Pushed onto the
    /// surrounding NavigationStack via `.navigationDestination(item:)` so
    /// we don't have to round-trip through DeepLinkRouter (which is wired
    /// to the legacy CompanionTodayView, not this chat-first surface).
    @State private var openArticleId: String?
    /// Brief history sheet toggle; populated from a toolbar tap.
    @State private var showBriefHistory = false
    /// Topic brief sheet toggle.
    @State private var showTopicBrief = false
    /// Local navigation target for `nebularnews://brief/{id}` deep links
    /// fired from APNs taps or widgets while the user is on this view.
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

                if isLoading && messages.isEmpty {
                    ProgressView("Loading brief…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                Divider()
                inputBar
            }
            .navigationTitle("Today")
            .toolbar {
                // Order matches the legacy CompanionTodayView (history left,
                // refresh right) so the icons feel familiar to existing users.
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
            // navigationDestination must live inside the NavigationStack
            // so taps on a brief bullet actually push CompanionArticleDetailView.
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
        // Today IS the assistant conversation now; the floating FAB
        // would just be a second handle to the same thread on the same
        // surface. Hide while on Today, restore on disappear so other
        // tabs (Discover / Library / article detail) keep the FAB.
        .onAppear { coordinator.hideFloatingButton = true }
        .onDisappear { coordinator.hideFloatingButton = false }
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
        do {
            // Today + overlay share the assistant thread. The server's
            // GET /chat/assistant calls ensureTodayBriefSeed before
            // returning, so the brief shows up in the message list as
            // the latest assistant message.
            let payload: CompanionChatPayload = try await APIClient.shared.request(
                path: "api/chat/assistant"
            )
            thread = payload.thread
            messages = payload.messages.filter { $0.role != "system" }
            // Pin the coordinator to the same thread so sendMessage
            // (used by the input bar + Tell me more) writes here.
            coordinator.currentThreadId = payload.thread?.id
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called once per view appearance. If the seeded brief is older than
    /// the staleness threshold, regenerates in the background and re-loads
    /// the thread. Idempotent — running the same check twice during one
    /// open is harmless because regenerateBrief() blocks on the same
    /// request the cron would otherwise issue.
    private func refreshIfStale() async {
        guard !isLoading else { return }
        let seed = messages.first(where: { $0.kind == "brief_seed" })
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

    // MARK: - Message list

    /// Native List drives the chat thread so each brief bullet gets
    /// SwiftUI's `.swipeActions` for free — no custom drag gesture
    /// fighting the parent ScrollView for vertical scroll. Brief seeds
    /// expand into a Section (header + bullet rows); other chat messages
    /// render as a single transparent row containing the bubble.
    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(messages) { msg in
                    messageRows(for: msg)
                }
                // Live-streaming bubble — coordinator.streamingContent
                // grows as deltas arrive; once isStreaming flips to false
                // we pull the persisted version from the server (see
                // .onChange below) and this view disappears as the real
                // assistant message takes over.
                if coordinator.isStreaming && !coordinator.streamingContent.isEmpty {
                    streamingBubble
                        .id("streamingBubble")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
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
            // Drag the message list down to dismiss the keyboard, the
            // same gesture Messages uses. Without this there's no way
            // to close the keyboard once the input bar steals focus.
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: coordinator.streamingContent) {
                withAnimation { proxy.scrollTo("streamingBubble", anchor: .bottom) }
            }
            .onChange(of: coordinator.isStreaming) { wasStreaming, isStreaming in
                // Stream just ended — refresh from the server so the
                // committed message replaces the transient bubble.
                if wasStreaming && !isStreaming {
                    Task { await loadThread() }
                }
            }
        }
    }

    /// Mirrors AssistantChatBubble's assistant rendering for the live
    /// streaming case: small sparkle avatar + secondary-tinted bubble.
    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1), in: Circle())
            Text(coordinator.streamingContent)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.platformSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func messageRows(for msg: CompanionChatMessage) -> some View {
        if msg.kind == "brief_seed", let brief = SeededBrief.parse(content: msg.content) {
            briefSection(brief: brief, anchorId: msg.id)
        } else {
            AssistantChatBubble(message: msg) { _ in }
                .id(msg.id)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
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

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about today…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                let text = inputText
                inputText = ""
                Task { await sendFollowUp(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Sends a message into the unified Today/assistant thread. Used by
    /// the input bar AND by the bullet "Tell me more" action — both
    /// land in the same conversation and stream inline. The post-stream
    /// refresh is handled by `.onChange(of: coordinator.isStreaming)`
    /// in `messageList`, so this just kicks off the send.
    private func sendFollowUp(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, thread?.id != nil else { return }
        coordinator.currentContext = AIPageContext(
            pageType: "today_brief",
            pageLabel: "Today brief",
            briefSummary: messages.first(where: { $0.kind == "brief_seed" })?.content
        )
        await coordinator.sendMessage(trimmed)
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
        case .tellMeMore(let prompt):
            // Route inline through the same conversation — no overlay
            // popup. Same pipeline as the input bar.
            Task { await sendFollowUp("Tell me more about: \(prompt)") }
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
            threadId: thread?.id ?? "",
            role: "assistant",
            content: marker,
            tokenCount: nil,
            provider: nil,
            model: nil,
            createdAt: Int(Date().timeIntervalSince1970),
            messageKind: "tool_result"
        )
        messages.append(msg)
    }

}
