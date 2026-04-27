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
            Task { await runServerTool(name: "save_articles", args: ["article_ids": articleIds]) }
        case .reactUp(let articleIds):
            Task { await runServerTool(name: "react_to_articles", args: ["article_ids": articleIds, "value": 1]) }
        case .reactDown(let articleIds):
            Task { await runServerTool(name: "react_to_articles", args: ["article_ids": articleIds, "value": -1]) }
        case .dismiss(let signature, let articleIds):
            dismissContext = DismissContext(signature: signature, articleIds: articleIds)
        case .tellMeMore(let prompt):
            Task { await sendFollowUp("Tell me more about: \(prompt)") }
        case .openArticle(let articleId):
            if let url = URL(string: "nebularnews://article/\(articleId)") {
                deepLinkRouter.handle(url)
            }
        }
    }

    /// Posts a synthetic user turn to /chat/assistant so the AI registers
    /// the action and emits the appropriate undo chip into the thread.
    /// Simpler than wiring a separate "execute server tool" endpoint.
    private func runServerTool(name: String, args: [String: Any]) async {
        // For first version we just append a user-message describing the
        // intent. The AI then calls the relevant tool. This keeps the
        // round-trip in one well-tested path. A future optimization could
        // call the tool directly via a new /chat/exec-tool endpoint to skip
        // the intent-recognition step.
        guard let threadId = thread?.id else { return }
        let prompt = synthesizePrompt(for: name, args: args)
        let context = AIPageContext(
            pageType: "today_brief",
            pageLabel: "Today brief",
            briefSummary: messages.first(where: { $0.kind == "brief_seed" })?.content
        )
        coordinator.currentContext = context
        coordinator.currentThreadId = threadId
        await coordinator.sendMessage(prompt)
        await loadThread()
    }

    private func synthesizePrompt(for tool: String, args: [String: Any]) -> String {
        switch tool {
        case "save_articles":
            if let ids = args["article_ids"] as? [String] {
                return "Save these articles to my reading list: \(ids.joined(separator: ", "))"
            }
        case "react_to_articles":
            let value = args["value"] as? Int ?? 1
            if let ids = args["article_ids"] as? [String] {
                return "Mark a \(value > 0 ? "👍 like" : "👎 dislike") on these articles: \(ids.joined(separator: ", "))"
            }
        default: break
        }
        return "Run tool \(tool)"
    }
}
