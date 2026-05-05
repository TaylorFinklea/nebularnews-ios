import SwiftUI

/// Root of the Agent tab. Lists the user's conversations newest-first;
/// pushing a row enters the chat surface for that conversation. The
/// "+" toolbar starts a fresh conversation. When `appState.pendingAgentConversation`
/// is set (because Today's "Tell me more" or article-detail's "Open in
/// Agent" routed here), this view auto-creates the pinned conversation,
/// pushes into it, queues the prompt, and clears the pending flag.
struct AgentConversationsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentConversationsCoordinator.self) private var coordinator
    @Environment(AIAssistantCoordinator.self) private var ai
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    /// Active conversation id pushed onto the local NavigationStack.
    /// Bound to `navigationDestination(item:)` so we can drive pushes
    /// programmatically (e.g. when handling pendingAgentConversation).
    @State private var pushed: String?

    /// Auto-send queue keyed by conversation id. Set when a brand-new
    /// conversation is created with a `prompt` from the pending flow;
    /// AgentConversationView reads + clears it on first appear.
    @State private var pendingPromptByConversation: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                if coordinator.conversations.isEmpty && !coordinator.isLoadingList {
                    emptyState
                } else {
                    ForEach(coordinator.conversations) { c in
                        Button {
                            pushed = c.id
                        } label: {
                            row(for: c)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await deleteConversation(c.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                if let err = coordinator.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Agent")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await startNewConversation() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New conversation")
                }
            }
            .refreshable { await coordinator.refresh() }
            .navigationDestination(item: $pushed) { conversationId in
                let pending = pendingPromptByConversation[conversationId]
                AgentConversationView(
                    conversationId: conversationId,
                    autoSendPrompt: pending,
                    onAutoSendConsumed: {
                        pendingPromptByConversation[conversationId] = nil
                    }
                )
            }
        }
        .task {
            if coordinator.conversations.isEmpty {
                await coordinator.refresh()
            }
            await handlePendingConversation()
            handlePendingDeepLink()
        }
        .onChange(of: appState.pendingAgentConversation) { _, _ in
            Task { await handlePendingConversation() }
        }
        .onChange(of: deepLinkRouter.pendingAgentConversationId) { _, _ in
            handlePendingDeepLink()
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("No conversations yet")
                .font(.headline)
            Text("Tap + to start chatting, or tap \u{201C}Tell me more\u{201D} on a brief bullet to anchor a conversation to that article.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    private func row(for c: AgentConversationSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: c.hasPinnedArticle ? "doc.text" : "bubble.left.and.text.bubble.right")
                .font(.title3)
                .foregroundStyle(c.hasPinnedArticle ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayTitle(for: c))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(relativeTime(c.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let preview = c.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(c.messageCount) message\(c.messageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func displayTitle(for c: AgentConversationSummary) -> String {
        if let t = c.title, !t.isEmpty { return t }
        if let preview = c.lastMessagePreview, !preview.isEmpty { return preview }
        return "Untitled"
    }

    private func relativeTime(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func startNewConversation() async {
        do {
            let new = try await SupabaseManager.shared.createAgentConversation()
            coordinator.insertNew(new)
            pushed = new.id
        } catch {
            await coordinator.refresh()
        }
    }

    private func handlePendingConversation() async {
        guard let pending = appState.pendingAgentConversation else { return }
        appState.pendingAgentConversation = nil
        do {
            let new = try await SupabaseManager.shared.createAgentConversation(
                articleId: pending.articleId,
                title: pending.articleTitle
            )
            coordinator.insertNew(new)
            if let prompt = pending.prompt, !prompt.isEmpty {
                pendingPromptByConversation[new.id] = prompt
            }
            pushed = new.id
        } catch {
            // Silent — the user can still tap + manually.
        }
    }

    private func handlePendingDeepLink() {
        guard let id = deepLinkRouter.pendingAgentConversationId, !id.isEmpty else { return }
        deepLinkRouter.clearPendingAgentConversation()
        pushed = id
    }

    private func deleteConversation(_ id: String) async {
        do {
            try await SupabaseManager.shared.deleteAgentConversation(id: id)
            coordinator.remove(id: id)
        } catch {
            // Re-fetch to stay consistent with server.
            await coordinator.refresh()
        }
    }
}

