import Foundation
import NebularNewsKit
import os

/// Drives an on-device chat response when the user's tier resolves to
/// `.onDevice` — `FoundationModelsEngine.streamChat` produces incremental
/// text chunks; we wrap them in the same `ChatDelta` shape that
/// `StreamingChatService` produces for the server SSE path so the
/// `AIAssistantCoordinator` consumer doesn't care which side generated
/// the response.
///
/// On-device generation has no MCP / tool support, so this stream never
/// emits `.toolServerResult` / `.toolClientCall` / `.toolProposal` —
/// the coordinator already handles tool-free streams gracefully.
enum OnDeviceAssistantStream {
    private static let logger = Logger(subsystem: "com.nebularnews", category: "OnDeviceAssistant")
    private static let engine = FoundationModelsEngine()

    /// Cap on history characters fed to the model. The system model
    /// has a small context window; truncating from the oldest message
    /// keeps recent turns intact while protecting against runaway
    /// prompt length on long-running threads.
    private static let maxHistoryChars = 4_000

    /// Stream an assistant response generated on-device. `history`
    /// includes the current optimistic user message at the end (the
    /// coordinator appends it before invoking us). `articleSnapshot`
    /// is optional and lets article-detail chats include the article
    /// body in the prompt.
    static func streamOnDeviceAssistant(
        content: String,
        history: [CompanionChatMessage],
        articleSnapshot: ArticleSnapshot? = nil
    ) -> AsyncStream<StreamingChatService.ChatDelta> {
        AsyncStream { continuation in
            let task = Task {
                guard FoundationModelsEngine.runtimeAvailable else {
                    continuation.yield(.error(unavailableMessage))
                    continuation.finish()
                    return
                }

                let trimmed = trimHistory(history)
                let systemPrompt = baseSystemPrompt(hasArticle: articleSnapshot != nil)
                var generationMessages: [GenerationChatMessage] = [
                    GenerationChatMessage(role: "system", content: systemPrompt)
                ]
                for msg in trimmed where msg.role == "user" || msg.role == "assistant" {
                    let role = msg.role == "user" ? "user" : "assistant"
                    let body = stripAssistantMarkers(msg.content)
                    guard !body.isEmpty else { continue }
                    generationMessages.append(GenerationChatMessage(role: role, content: body))
                }

                var accumulated = ""
                let stream = engine.streamChat(messages: generationMessages, articleContext: articleSnapshot)
                do {
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        accumulated += delta
                        continuation.yield(.text(delta))
                    }
                } catch {
                    let mapped = mapEngineError(error)
                    continuation.yield(.error(mapped))
                    continuation.finish()
                    return
                }

                // Synthetic done event — usage is zero tokens for on-device.
                continuation.yield(.done(content: accumulated, usage: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0)))
                continuation.finish()

                // Best-effort persist to server thread so DailyConversationsView
                // shows on-device turns under their local day.
                if !accumulated.isEmpty {
                    do {
                        _ = try await SupabaseManager.shared.persistAssistantMessages(
                            userMessage: content,
                            assistantMessage: accumulated
                        )
                    } catch {
                        // Non-fatal — the message is in coordinator.messages
                        // already. Sync resumes on the next foregrounding /
                        // user message that triggers another persist call.
                        logger.warning("Persist on-device turn failed: \(error.localizedDescription)")
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private static let unavailableMessage = "On-device AI is unavailable on this device. Add an API key or subscribe to chat."

    private static func baseSystemPrompt(hasArticle: Bool) -> String {
        let core = "You are NebularNews's assistant running on-device. Be concise, accurate, and helpful. You cannot search the web, fetch new articles, or perform any actions — only answer questions using the conversation context."
        if hasArticle {
            return core + " The user is reading the article shown in the prompt; ground your answers in its content when relevant."
        }
        return core
    }

    /// Drops the [[tool:...]] / [[article:...]] markers the parser
    /// inserts for server-tool chips — they're meaningless on-device
    /// and would confuse the model.
    private static func stripAssistantMarkers(_ text: String) -> String {
        var out = text
        // Crude but safe: drop everything between [[ and ]] inclusive.
        while let openRange = out.range(of: "[["), let closeRange = out.range(of: "]]", range: openRange.upperBound..<out.endIndex) {
            out.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trim history from the oldest end until the total body length is
    /// below the cap. Always preserves the last message (the user's
    /// current turn) regardless of length.
    private static func trimHistory(_ history: [CompanionChatMessage]) -> [CompanionChatMessage] {
        guard !history.isEmpty else { return history }
        var working = history
        while working.count > 1 {
            let total = working.reduce(0) { $0 + $1.content.count }
            if total <= maxHistoryChars { break }
            working.removeFirst()
        }
        return working
    }

    private static func mapEngineError(_ error: Error) -> String {
        if let fm = error as? FoundationModelsEngineError {
            switch fm {
            case .unavailable: return unavailableMessage
            case .invalidResponse: return "On-device AI returned an unexpected response. Try again."
            }
        }
        return error.localizedDescription
    }
}
