import SwiftUI

struct MultiArticleChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if messages.isEmpty && !isLoading {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            }

                            ForEach(messages) { message in
                                MultiChatBubble(message: message)
                                    .id(message.id)
                            }

                            if isSending {
                                MultiChatTypingIndicator()
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
                            withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
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

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask about today's news…", text: $inputText, axis: .vertical)
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
            .navigationTitle("Today's News")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadChat() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ask about today's news")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Get insights across your recent articles — trends, connections, and analysis.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func loadChat() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.supabase.fetchMultiChat()
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

        let tempId = UUID().uuidString
        let optimistic = CompanionChatMessage(
            id: tempId, threadId: "", role: "user", content: content,
            tokenCount: nil, provider: nil, model: nil,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        messages.append(optimistic)

        do {
            let payload = try await appState.supabase.sendMultiChatMessage(content: content)
            messages = payload.messages
        } catch {
            messages.removeAll { $0.id == tempId }
            inputText = savedInput
            errorMessage = error.localizedDescription
        }

        isSending = false
    }
}

// MARK: - Multi Chat Bubble (reuses patterns from CompanionArticleChatView)

private struct MultiChatBubble: View {
    let message: CompanionChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                Image(systemName: "newspaper")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.opacity(0.1), in: Circle())
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

private struct MultiChatTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "newspaper")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1), in: Circle())

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
