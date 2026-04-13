import SwiftUI

/// The bottom sheet content for the floating AI assistant.
struct AIAssistantSheetView: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator
    @State private var inputText = ""
    @State private var showHistory = false

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if coordinator.messages.isEmpty && !coordinator.isStreaming {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }

                            ForEach(coordinator.messages) { message in
                                AssistantChatBubble(message: message) { articleId in
                                    // TODO: Navigate to article via DeepLinkRouter
                                }
                                .id(message.id)
                            }

                            if coordinator.isStreaming {
                                streamingBubble
                                    .id("streaming")
                            }

                            // Follow-up suggestions
                            if !coordinator.suggestedQuestions.isEmpty && !coordinator.isStreaming {
                                followUpSuggestions
                                    .id("suggestions")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: coordinator.messages.count) {
                        withAnimation {
                            if let last = coordinator.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: coordinator.streamingContent) {
                        if coordinator.isStreaming {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }

                if !coordinator.errorMessage.isEmpty {
                    Text(coordinator.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }

                Divider()

                // Context indicator
                if let context = coordinator.currentContext {
                    HStack(spacing: 4) {
                        Image(systemName: iconForPageType(context.pageType))
                            .font(.caption2)
                        Text(context.pageLabel)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                inputBar
            }
            .navigationTitle("AI Assistant")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await coordinator.startNewConversation() }
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
                }
            }
            .navigationDestination(isPresented: $showHistory) {
                AssistantHistoryView()
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.purple.opacity(0.6))
            Text("AI Assistant")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask about your news, find articles, get insights — I know what page you're on.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1), in: Circle())

            if coordinator.streamingContent.isEmpty {
                Text("▊")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.platformSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(LocalizedStringKey(coordinator.streamingContent))
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.platformSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Spacer(minLength: 40)
        }
    }

    private var followUpSuggestions: some View {
        VStack(spacing: 6) {
            ForEach(coordinator.suggestedQuestions, id: \.self) { question in
                Button {
                    inputText = question
                    coordinator.suggestedQuestions = []
                    Task { await coordinator.sendMessage(question) }
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                let text = inputText
                inputText = ""
                Task { await coordinator.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isStreaming
                        ? Color.secondary : Color.accentColor
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func iconForPageType(_ type: String) -> String {
        switch type {
        case "today": return "sun.max"
        case "articles": return "doc.text"
        case "article_detail": return "doc.richtext"
        case "discover": return "safari"
        case "reading_list": return "bookmark"
        case "feeds": return "antenna.radiowaves.left.and.right"
        default: return "circle"
        }
    }
}
