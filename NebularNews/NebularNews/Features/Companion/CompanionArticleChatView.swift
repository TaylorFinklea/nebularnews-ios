import SwiftUI

struct CompanionArticleChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let articleId: String
    let articleTitle: String?

    @State private var messages: [CompanionChatMessage] = []
    @State private var suggestedQuestions: [String] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var isStreaming = false
    @State private var streamingContent = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if messages.isEmpty && !isLoading {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            }

                            ForEach(messages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }

                            if isStreaming {
                                StreamingMessageView(content: streamingContent)
                                    .id("streaming")
                            } else if isSending {
                                TypingIndicator()
                                    .id("thinking")
                            }

                            // Follow-up suggestions after messages
                            if !suggestedQuestions.isEmpty && !messages.isEmpty && !isStreaming && !isSending {
                                followUpSuggestions
                                    .id("follow-ups")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            if let last = messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isSending) {
                        if isSending {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: streamingContent) {
                        if isStreaming {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider()

                chatInputBar
            }
            .navigationTitle(articleTitle ?? "Chat")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadChat() }
        }
    }

    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about this article…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                        ? Color.secondary : Color.accentColor
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ask about this article")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Get summaries, ask questions, or explore the topic further.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !suggestedQuestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            inputText = question
                            Task { await sendMessage() }
                        } label: {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    private var followUpSuggestions: some View {
        VStack(spacing: 6) {
            ForEach(suggestedQuestions, id: \.self) { question in
                Button {
                    inputText = question
                    suggestedQuestions = []
                    Task { await sendMessage() }
                } label: {
                    Text(question)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func loadChat() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let chatPayload = appState.supabase.fetchChat(articleId: articleId)
            async let questions = appState.supabase.fetchSuggestedQuestions(articleId: articleId)

            let (payload, fetchedQuestions) = try await (chatPayload, questions)
            messages = payload.messages
            suggestedQuestions = fetchedQuestions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendMessage() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        errorMessage = ""
        isSending = true
        let savedInput = inputText
        inputText = ""

        // Optimistic user message
        let tempId = UUID().uuidString
        let optimistic = CompanionChatMessage(
            id: tempId,
            threadId: "",
            role: "user",
            content: content,
            tokenCount: nil,
            provider: nil,
            model: nil,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        messages.append(optimistic)

        // Stream the response
        streamingContent = ""
        isSending = false
        isStreaming = true

        let stream = StreamingChatService.shared.streamChatMessage(
            articleId: articleId,
            content: content
        )

        var finalContent = ""
        for await delta in stream {
            switch delta {
            case .text(let text):
                streamingContent += text
            case .done(let content, _):
                finalContent = content
            case .error(let msg):
                errorMessage = msg
            }
        }

        isStreaming = false

        if !finalContent.isEmpty {
            // Parse follow-up suggestions (lines starting with >>).
            let lines = finalContent.components(separatedBy: "\n")
            let textLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">>") }
            let parsedSuggestions = lines.compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(">>") else { return nil }
                let q = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return q.isEmpty ? nil : q
            }

            let cleanContent = textLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let assistantMsg = CompanionChatMessage(
                id: UUID().uuidString,
                threadId: "",
                role: "assistant",
                content: cleanContent,
                tokenCount: nil,
                provider: nil,
                model: nil,
                createdAt: Int(Date().timeIntervalSince1970)
            )
            messages.append(assistantMsg)
            streamingContent = ""

            if !parsedSuggestions.isEmpty {
                suggestedQuestions = parsedSuggestions
            }
        } else if !errorMessage.isEmpty {
            // On error, remove the optimistic user message and restore input
            messages.removeAll { $0.id == tempId }
            inputText = savedInput
            streamingContent = ""
        }
    }
}

// MARK: - Chat Message View

private struct ChatMessageView: View {
    let message: CompanionChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .frame(width: 24, height: 24)
                    .background(Color.purple.opacity(0.1), in: Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if isUser {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    // AI response — render as markdown-styled text
                    Text(LocalizedStringKey(message.content))
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.platformSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let model = message.model, !isUser {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Streaming Message View

private struct StreamingMessageView: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                if content.isEmpty {
                    // Show cursor while waiting for first token
                    Text("▊")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.platformSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text(LocalizedStringKey(content))
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.platformSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1), in: Circle())

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(animating ? 0.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 40)
        }
        .onAppear { animating = true }
    }
}
