import Foundation
import SwiftUI
import os

/// Central coordinator for the floating AI assistant.
///
/// Owns the assistant's state (sheet presentation, messages, streaming,
/// page context) and is injected at the app level via `.environment()`.
@MainActor
@Observable
final class AIAssistantCoordinator {

    // MARK: - Sheet State

    var isSheetPresented = false
    var hideFloatingButton = false

    // MARK: - Page Context

    var currentContext: AIPageContext?
    private var lastSentContext: AIPageContext?

    // MARK: - Chat State

    var messages: [CompanionChatMessage] = []
    var currentThreadId: String?
    var isStreaming = false
    var streamingContent = ""
    var isSending = false
    var errorMessage = ""
    var suggestedQuestions: [String] = []

    // MARK: - History

    var recentThreads: [AssistantThreadSummary] = []

    private let logger = Logger(subsystem: "com.nebularnews", category: "AIAssistant")

    // MARK: - Context Management

    func updateContext(_ context: AIPageContext) {
        currentContext = context
    }

    // MARK: - Actions

    func toggle() {
        isSheetPresented.toggle()
        if isSheetPresented && messages.isEmpty {
            Task { await loadCurrentThread() }
        }
    }

    func sendMessage(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let context = currentContext else { return }

        errorMessage = ""
        isSending = true

        // Optimistic user message
        let tempId = UUID().uuidString
        let optimistic = CompanionChatMessage(
            id: tempId, threadId: currentThreadId ?? "", role: "user",
            content: content, tokenCount: nil, provider: nil, model: nil,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        messages.append(optimistic)

        // Stream the response
        streamingContent = ""
        isSending = false
        isStreaming = true

        let stream = StreamingChatService.shared.streamAssistantMessage(
            content: content,
            pageContext: context,
            threadId: currentThreadId
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
            let (cleanContent, parsedSuggestions) = AssistantMessageParser.extractSuggestions(from: finalContent)

            let assistantMsg = CompanionChatMessage(
                id: UUID().uuidString, threadId: currentThreadId ?? "", role: "assistant",
                content: cleanContent, tokenCount: nil, provider: nil, model: nil,
                createdAt: Int(Date().timeIntervalSince1970)
            )
            messages.append(assistantMsg)
            streamingContent = ""

            if !parsedSuggestions.isEmpty {
                suggestedQuestions = parsedSuggestions
            }
        } else if !errorMessage.isEmpty {
            messages.removeAll { $0.id == tempId }
            streamingContent = ""
        }

        lastSentContext = context
    }

    func loadCurrentThread() async {
        guard APIClient.shared.hasSession else { return }

        do {
            let payload: CompanionChatPayload = try await APIClient.shared.request(
                path: "api/chat/assistant"
            )
            messages = payload.messages.filter { $0.role != "system" }
            if let thread = payload.thread {
                currentThreadId = thread.id
            }
        } catch {
            logger.error("Failed to load assistant thread: \(error.localizedDescription)")
        }
    }

    func loadHistory() async {
        guard APIClient.shared.hasSession else { return }

        do {
            let threads: [AssistantThreadSummary] = try await APIClient.shared.request(
                path: "api/chat/assistant/history"
            )
            recentThreads = threads
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }

    func startNewConversation() async {
        guard APIClient.shared.hasSession else { return }

        do {
            struct NewThreadResponse: Decodable { let threadId: String }
            let response: NewThreadResponse = try await APIClient.shared.request(
                method: "POST",
                path: "api/chat/assistant/new"
            )
            currentThreadId = response.threadId
            messages = []
            suggestedQuestions = []
            streamingContent = ""
        } catch {
            logger.error("Failed to create new thread: \(error.localizedDescription)")
        }
    }

    func loadThread(_ threadId: String) async {
        // Load a specific thread from history.
        currentThreadId = threadId
        messages = []

        do {
            let payload: CompanionChatPayload = try await APIClient.shared.request(
                path: "api/chat/assistant",
                queryItems: [URLQueryItem(name: "threadId", value: threadId)]
            )
            messages = payload.messages.filter { $0.role != "system" }
        } catch {
            logger.error("Failed to load thread \(threadId): \(error.localizedDescription)")
        }
    }
}
