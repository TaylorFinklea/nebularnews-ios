import Foundation
import SwiftUI
import os
import Combine

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

    /// Small caption to render above the streaming bubble while a
    /// response is generating. Today only the on-device tier surfaces a
    /// badge; paid + BYOK paths look the same as before. `nil` when no
    /// caption should be shown.
    var tierBadge: String? {
        AIRouting.shared.current.streamingBadge
    }

    // MARK: - History

    var recentThreads: [AssistantThreadSummary] = []

    /// Injected by the overlay view; handles client-side tool calls.
    /// Returns a (summary, succeeded) pair for confirmation-chip rendering.
    var clientToolHandler: ((String, [String: AnyCodable]) -> (summary: String, succeeded: Bool))?

    // MARK: - Guardrails (M11)

    /// A pending tool proposal awaiting user confirmation. Set when a
    /// `tool_call_propose` SSE event arrives; cleared when resolved.
    var pendingProposal: AIToolConfirmationSheet.PendingProposal?

    /// A pending undo toast for tools running under "Undo only" policy.
    var pendingUndoToast: AIUndoToast.PendingUndoToast?
    private var undoToastTask: Task<Void, Never>?

    /// Injected by the overlay — provides the current guardrail policies.
    var guardrailsPolicy: AIGuardrailsPolicy?

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

        let policies = guardrailsPolicy?.snapshot()
        // Free-tier (no BYOK key, no subscription, Apple Intelligence available)
        // runs the response on-device via FoundationModels. BYOK + paid go
        // through the server SSE path with full MCP tool support. The
        // `.unavailable` case (older device with no key or sub) short-
        // circuits to a clear error rather than letting the server return
        // an opaque 503.
        let tier = AIRouting.shared.current
        let stream: AsyncStream<StreamingChatService.ChatDelta>
        switch tier {
        case .onDevice:
            stream = OnDeviceAssistantStream.streamOnDeviceAssistant(
                content: content,
                history: messages,
                articleSnapshot: nil
            )
        case .byok, .subscription:
            stream = StreamingChatService.shared.streamAssistantMessage(
                content: content,
                pageContext: context,
                threadId: currentThreadId,
                guardrailPolicies: policies
            )
        case .unavailable:
            stream = AsyncStream { continuation in
                continuation.yield(.error("AI is not configured. Add an API key in Settings or subscribe to enable chat."))
                continuation.finish()
            }
        }

        var finalContent = ""
        var proposalReceived = false
        for await delta in stream {
            switch delta {
            case .text(let text):
                streamingContent += text
            case .done(let content, _):
                finalContent = content
            case .error(let msg):
                errorMessage = msg
            case .toolServerResult(let name, let summary, let succeeded, let undoTool, let undoArgsB64):
                // Backend already ran the tool — render as a confirmation chip inline.
                streamingContent += AssistantMessageParser.toolMarker(
                    name: name,
                    summary: summary,
                    succeeded: succeeded,
                    undoTool: undoTool,
                    undoArgsB64: undoArgsB64
                )
                // Show undo toast if this is a governed tool under "Undo only" policy.
                if let undoTool, !undoTool.isEmpty, let undoArgsB64, !undoArgsB64.isEmpty,
                   AIGuardrailsPolicy.governedTools.contains(name),
                   guardrailsPolicy?.mode(for: name) == .undoOnly {
                    showUndoToast(summary: summary, undoTool: undoTool, undoArgsB64: undoArgsB64)
                }
            case .toolClientCall(let name, let args):
                // Dispatch locally and render the result as a chip.
                let result = clientToolHandler?(name, args) ?? (summary: "Unhandled action: \(name)", succeeded: false)
                streamingContent += AssistantMessageParser.toolMarker(name: name, summary: result.summary, succeeded: result.succeeded)
            case .toolProposal(let id, let name, _, let summary, let detail, let contextHint):
                pendingProposal = .init(
                    proposeId: id, toolName: name, summary: summary,
                    detail: detail, contextHint: contextHint
                )
                isStreaming = false
                proposalReceived = true
                break
            }
            if proposalReceived { break }
        }

        // The backend emits tool chips via SSE events *in addition to* including
        // them in the final `done` payload. Keep the locally-accumulated
        // streamingContent as the source of truth so the UI matches what it just
        // watched stream in.
        if !streamingContent.isEmpty && !finalContent.contains("[[tool:") {
            finalContent = streamingContent
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

    /// Invoked from AssistantChatBubble when the user taps Undo on a tool chip.
    /// POSTs the server-provided inverse action, then appends a confirmation chip
    /// to the most recent assistant message so the user sees the undo landed.
    func undoTool(tool: String, argsB64: String) async {
        guard APIClient.shared.hasSession else { return }
        guard let argsData = Data(base64Encoded: argsB64),
              let argsObj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            logger.warning("Could not decode undo args")
            return
        }
        let body: [String: Any] = ["tool": tool, "args": argsObj]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: APIClient.shared.baseURL.appendingPathComponent("api/chat/undo-tool"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = APIClient.shared.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        struct UndoResponse: Decodable { let summary: String; let succeeded: Bool }
        struct UndoError: Decodable { let message: String? }
        struct UndoEnvelope: Decodable { let ok: Bool; let data: UndoResponse?; let error: UndoError? }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            if httpResponse.statusCode >= 400 {
                throw APIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
            let envelope = try JSONDecoder().decode(UndoEnvelope.self, from: data)
            if let payload = envelope.data, envelope.ok {
                appendToolChipToLastAssistantMessage(name: "undo", summary: payload.summary, succeeded: payload.succeeded)
            } else {
                appendToolChipToLastAssistantMessage(name: "undo", summary: envelope.error?.message ?? "Undo failed", succeeded: false)
            }
        } catch {
            logger.error("Undo failed: \(error.localizedDescription)")
            appendToolChipToLastAssistantMessage(name: "undo", summary: "Undo failed", succeeded: false)
        }
    }

    // MARK: - Proposal resolution

    /// Called when the user approves or rejects a pending tool proposal.
    func resolveProposal(
        approve: Bool,
        edits: [String: AnyCodable]? = nil,
        dontAskAgain: Bool = false
    ) async {
        guard let p = pendingProposal else { return }
        pendingProposal = nil

        if dontAskAgain {
            guardrailsPolicy?.setMode(.undoOnly, for: p.toolName)
        }

        isStreaming = true
        streamingContent = ""

        let stream = StreamingChatService.shared.streamConfirmTool(
            proposeId: p.proposeId,
            decision: approve ? "approve" : "reject",
            edits: edits
        )

        var finalContent = ""
        var proposalReceived = false
        for await delta in stream {
            switch delta {
            case .text(let text):
                streamingContent += text
            case .done(let content, _):
                finalContent = content
            case .error(let msg):
                if msg == "proposal_expired" {
                    // Expired — show a soft inline message.
                    streamingContent += "\n\n*That action timed out. Ask again if you'd still like to do it.*"
                    finalContent = streamingContent
                } else {
                    errorMessage = msg
                }
            case .toolServerResult(let name, let summary, let succeeded, let undoTool, let undoArgsB64):
                streamingContent += AssistantMessageParser.toolMarker(
                    name: name, summary: summary, succeeded: succeeded,
                    undoTool: undoTool, undoArgsB64: undoArgsB64
                )
                if let undoTool, !undoTool.isEmpty, let undoArgsB64, !undoArgsB64.isEmpty,
                   AIGuardrailsPolicy.governedTools.contains(name),
                   guardrailsPolicy?.mode(for: name) == .undoOnly {
                    showUndoToast(summary: summary, undoTool: undoTool, undoArgsB64: undoArgsB64)
                }
            case .toolClientCall(let name, let args):
                let result = clientToolHandler?(name, args) ?? (summary: "Unhandled action: \(name)", succeeded: false)
                streamingContent += AssistantMessageParser.toolMarker(name: name, summary: result.summary, succeeded: result.succeeded)
            case .toolProposal(let id, let name, _, let summary, let detail, let contextHint):
                // Chained proposal — set it and stop this drain.
                pendingProposal = .init(
                    proposeId: id, toolName: name, summary: summary,
                    detail: detail, contextHint: contextHint
                )
                isStreaming = false
                proposalReceived = true
                break
            }
            if proposalReceived { break }
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
        } else if !streamingContent.isEmpty {
            // Streaming content was set but finalContent wasn't — use streaming content.
            let (cleanContent, _) = AssistantMessageParser.extractSuggestions(from: streamingContent)
            let assistantMsg = CompanionChatMessage(
                id: UUID().uuidString, threadId: currentThreadId ?? "", role: "assistant",
                content: cleanContent, tokenCount: nil, provider: nil, model: nil,
                createdAt: Int(Date().timeIntervalSince1970)
            )
            messages.append(assistantMsg)
            streamingContent = ""
        }
    }

    // MARK: - Undo toast

    private func showUndoToast(summary: String, undoTool: String, undoArgsB64: String) {
        // Replace any existing toast — only one at a time.
        undoToastTask?.cancel()
        pendingUndoToast = .init(summary: summary, undoTool: undoTool, undoArgsB64: undoArgsB64)

        undoToastTask = Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000) // 7 seconds
            if !Task.isCancelled {
                pendingUndoToast = nil
            }
        }
    }

    func dismissUndoToast() {
        undoToastTask?.cancel()
        pendingUndoToast = nil
    }

    private func appendToolChipToLastAssistantMessage(name: String, summary: String, succeeded: Bool) {
        guard let idx = messages.lastIndex(where: { $0.role == "assistant" }) else { return }
        let marker = AssistantMessageParser.toolMarker(name: name, summary: summary, succeeded: succeeded)
        let original = messages[idx]
        let newContent = original.content + marker
        messages[idx] = CompanionChatMessage(
            id: original.id,
            threadId: original.threadId,
            role: original.role,
            content: newContent,
            tokenCount: original.tokenCount,
            provider: original.provider,
            model: original.model,
            createdAt: original.createdAt
        )
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
