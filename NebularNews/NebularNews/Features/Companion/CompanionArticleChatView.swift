import SwiftUI

struct CompanionArticleChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let articleId: String
    let articleTitle: String?

    @State private var messages: [CompanionChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty && !isLoading {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            }

                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if isSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                                .id("thinking")
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
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Ask about this article…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)

                    Button {
                        Task { await sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadChat() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Ask a question about this article")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadChat() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.mobileAPI.fetchChat(articleId: articleId)
            messages = payload.messages
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

        do {
            let payload = try await appState.mobileAPI.sendChatMessage(articleId: articleId, content: content)
            messages = payload.messages
        } catch {
            // Remove optimistic message on failure
            messages.removeAll { $0.id == tempId }
            inputText = savedInput
            errorMessage = error.localizedDescription
        }

        isSending = false
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: CompanionChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }

            Text(message.content)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !isUser { Spacer(minLength: 48) }
        }
    }
}
