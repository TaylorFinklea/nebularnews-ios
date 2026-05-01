import SwiftUI
import SwiftData

/// Chat-first Today tab. Renders a single thread (`__today_brief__`) where
/// the most recent assistant message is a structured news brief and any
/// follow-ups beneath it are normal text bubbles. The user can tap inline
/// chips on each bullet (save, react, dismiss, tell me more) or type a
/// free-form follow-up at the bottom.
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

    private struct DismissContext: Identifiable {
        let id = UUID()
        let signature: String
        let articleIds: [String]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            if dismissService == nil {
                dismissService = DismissedTopicService(context: modelContext)
            }
            dismissService?.cleanup()
            await loadThread()
            await refreshIfStale()
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
            let payload: CompanionChatPayload = try await APIClient.shared.request(
                path: "api/chat/__today_brief__"
            )
            thread = payload.thread
            messages = payload.messages.filter { $0.role != "system" }
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
            let suppressed_topics: [SuppressedTopicPayload]?
        }
        let _: BriefGenerateResponseEnvelope = try await APIClient.shared.request(
            method: "POST",
            path: "api/brief/generate",
            body: GenBody(lookback_hours: 12, suppressed_topics: suppressedTopics)
        )
    }

    /// Opaque envelope — we don't render the response, just need to await it.
    private struct BriefGenerateResponseEnvelope: Decodable {}

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        messageRow(msg)
                            .id(msg.id)
                            .padding(.horizontal)
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: CompanionChatMessage) -> some View {
        if msg.kind == "brief_seed", let brief = SeededBrief.parse(content: msg.content) {
            BriefMessageView(brief: brief, onAction: handleBulletAction)
        } else {
            AssistantChatBubble(message: msg) { _ in }
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

    /// Open the floating AI assistant sheet and seed it with `prompt`.
    /// Used by the bullet "Tell me more" action so the deeper exploration
    /// happens in the assistant thread rather than the inline Today thread.
    private func openAssistantWith(prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coordinator.currentContext = AIPageContext(
            pageType: "today_brief",
            pageLabel: "Today brief",
            briefSummary: messages.first(where: { $0.kind == "brief_seed" })?.content
        )
        // Switch the coordinator off the __today_brief__ thread so the
        // assistant thread receives the message; loadCurrentThread fetches
        // /api/chat/assistant and overwrites currentThreadId.
        await coordinator.loadCurrentThread()
        coordinator.isSheetPresented = true
        await coordinator.sendMessage(trimmed)
    }

    private func sendFollowUp(_ text: String) async {
        // Reuse the assistant streaming pipeline. The message is appended to
        // the same `__today_brief__` thread so the AI has full context of
        // what was in the brief.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let threadId = thread?.id else { return }
        let context = AIPageContext(
            pageType: "today_brief",
            pageLabel: "Today brief",
            briefSummary: messages.first(where: { $0.kind == "brief_seed" })?.content
        )
        coordinator.currentContext = context
        coordinator.currentThreadId = threadId
        await coordinator.sendMessage(trimmed)
        // Pull the latest server-side messages so chips & undo persist.
        await loadThread()
    }

    // MARK: - Bullet actions

    private func handleBulletAction(_ action: BriefMessageView.BulletAction) {
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
            Task { await openAssistantWith(prompt: "Tell me more about: \(prompt)") }
        case .openArticle(let articleId):
            if let url = URL(string: "nebularnews://article/\(articleId)") {
                deepLinkRouter.handle(url)
            }
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
