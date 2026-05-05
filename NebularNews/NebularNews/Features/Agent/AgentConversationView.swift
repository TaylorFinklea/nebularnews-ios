import SwiftUI

/// Chat surface for a single Agent conversation. Reuses the existing
/// `AIAssistantCoordinator` for streaming + tool dispatch; we just
/// point its thread id at this conversation and reset its in-memory
/// state on appear so switching conversations starts clean.
///
/// `autoSendPrompt` is consumed once on first appearance — set when
/// the user came in via "Tell me more" or "Open in Agent" so the
/// prompt sends itself instead of forcing the user to retype it.
struct AgentConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentConversationsCoordinator.self) private var conversations
    @Environment(AIAssistantCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    let conversationId: String
    var autoSendPrompt: String? = nil
    var onAutoSendConsumed: (() -> Void)? = nil

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var didConsumeAutoSend = false
    @FocusState private var isInputFocused: Bool

    private var visibleMessages: [CompanionChatMessage] {
        coordinator.messages.filter { $0.role != "system" }
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList

            if !coordinator.suggestedQuestions.isEmpty && !coordinator.isStreaming {
                suggestedQuestionsBar
            }

            Divider()
            inputBar
        }
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isInputFocused = false }
            }
        }
        .task { await openConversation() }
        .onDisappear {
            conversations.setActive(nil)
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                if isLoading && visibleMessages.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(visibleMessages) { msg in
                    AssistantChatBubble(message: msg) { _ in
                        // Article taps inside Agent are handled by the
                        // bubble itself (sheet from inside the bubble);
                        // we don't push at this level to avoid the
                        // nav-stack + per-conversation scroll race.
                    }
                    .id(msg.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                if coordinator.isStreaming && !coordinator.streamingContent.isEmpty {
                    streamingBubble
                        .id("streamingBubble")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                if !coordinator.errorMessage.isEmpty {
                    Text(coordinator.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: visibleMessages.count) {
                if let last = visibleMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: coordinator.streamingContent) {
                withAnimation { proxy.scrollTo("streamingBubble", anchor: .bottom) }
            }
        }
    }

    private var streamingBubble: some View {
        let segments = AssistantMessageParser.parse(coordinator.streamingContent)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                if let badge = coordinator.tierBadge {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.gen3")
                            .font(.caption2)
                        Text(badge)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    AssistantSegmentView(segment: segment) { _ in }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.platformSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 40)
        }
    }

    private var suggestedQuestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(coordinator.suggestedQuestions, id: \.self) { question in
                    Button {
                        coordinator.suggestedQuestions = []
                        Task { await sendMessage(question) }
                    } label: {
                        Text(question)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.10))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                let text = inputText
                inputText = ""
                Task { await sendMessage(text) }
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

    // MARK: - Actions

    private var navigationTitle: String {
        // Conversation title from the list (set by server heuristic on
        // first user message). Falls back to "Conversation" while the
        // title is null on a brand-new thread.
        conversations.conversations.first(where: { $0.id == conversationId })?.title ?? "Conversation"
    }

    private func openConversation() async {
        conversations.setActive(conversationId)
        // Reset shared coordinator state so switching conversations
        // starts clean (no stale streamingContent, suggestedQuestions,
        // errorMessage, or pending proposal from another thread).
        coordinator.messages = []
        coordinator.streamingContent = ""
        coordinator.suggestedQuestions = []
        coordinator.errorMessage = ""
        coordinator.currentThreadId = conversationId
        coordinator.currentContext = AIPageContext(
            pageType: "agent",
            pageLabel: "Agent"
        )

        isLoading = true
        await coordinator.loadThread(conversationId)
        isLoading = false

        if !didConsumeAutoSend, let prompt = autoSendPrompt, !prompt.isEmpty {
            didConsumeAutoSend = true
            onAutoSendConsumed?()
            await sendMessage(prompt)
        }
    }

    private func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await coordinator.sendMessage(trimmed)
        // Refresh the list-level summary so updated_at + last preview
        // reflect the new turn when the user pops back.
        Task { await conversations.refresh() }
    }
}
