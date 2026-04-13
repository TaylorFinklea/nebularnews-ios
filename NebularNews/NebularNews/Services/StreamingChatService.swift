import Foundation
import NebularNewsKit
import os

/// Consumes SSE streams from the Workers chat endpoints and publishes
/// incremental text deltas for live rendering in chat views.
final class StreamingChatService: Sendable {
    static let shared = StreamingChatService()

    private let api = APIClient.shared
    private let logger = Logger(subsystem: "com.nebularnews", category: "StreamingChat")

    /// A single chunk from the SSE stream.
    enum ChatDelta: Sendable {
        case text(String)
        case done(content: String, usage: TokenUsage)
        case error(String)
    }

    struct TokenUsage: Decodable, Sendable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
    }

    /// Send a chat message and return an `AsyncStream` of incremental deltas.
    func streamChatMessage(
        articleId: String,
        content: String
    ) -> AsyncStream<ChatDelta> {
        streamChat(path: "api/chat/\(articleId)", message: content)
    }

    /// Send a multi-article chat message and return an `AsyncStream` of deltas.
    func streamMultiChatMessage(
        content: String
    ) -> AsyncStream<ChatDelta> {
        streamChat(path: "api/chat/multi", message: content)
    }

    /// Send a message to the floating AI assistant with page context.
    func streamAssistantMessage(
        content: String,
        pageContext: AIPageContext,
        threadId: String?
    ) -> AsyncStream<ChatDelta> {
        streamAssistantChat(message: content, pageContext: pageContext, threadId: threadId)
    }

    // MARK: - Private

    private func streamAssistantChat(
        message: String,
        pageContext: AIPageContext,
        threadId: String?
    ) -> AsyncStream<ChatDelta> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performAssistantStream(message: message, pageContext: pageContext, threadId: threadId, continuation: continuation)
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performAssistantStream(
        message: String,
        pageContext: AIPageContext,
        threadId: String?,
        continuation: AsyncStream<ChatDelta>.Continuation
    ) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        var url = api.baseURL.appendingPathComponent("api/chat/assistant")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "stream", value: "true")]
        url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let token = api.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // BYOK headers
        let keychain = KeychainManager(service: "com.nebularnews.ios")
        if let key = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("anthropic", forHTTPHeaderField: "x-user-api-provider")
        } else if let key = keychain.get(forKey: KeychainManager.Key.openaiApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("openai", forHTTPHeaderField: "x-user-api-provider")
        }

        struct AssistantBody: Encodable {
            let message: String
            let pageContext: AIPageContext
            let threadId: String?
        }

        request.httpBody = try JSONEncoder().encode(AssistantBody(message: message, pageContext: pageContext, threadId: threadId))

        logger.debug("[STREAM] POST \(url.absoluteString)")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        if httpResponse.statusCode >= 400 { throw APIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)") }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonStr = String(trimmed.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8) else { continue }

            do {
                let event = try JSONDecoder().decode(SSEEvent.self, from: data)
                switch event.type {
                case "delta":
                    if let content = event.content { continuation.yield(.text(content)) }
                case "done":
                    let usage = TokenUsage(promptTokens: event.usage?.promptTokens, completionTokens: event.usage?.completionTokens, totalTokens: event.usage?.totalTokens)
                    continuation.yield(.done(content: event.content ?? "", usage: usage))
                case "error":
                    continuation.yield(.error(event.error ?? "Unknown error"))
                default: break
                }
            } catch {
                logger.warning("Failed to decode SSE: \(jsonStr)")
            }
        }
    }

    private func streamChat(path: String, message: String) -> AsyncStream<ChatDelta> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performStream(path: path, message: message, continuation: continuation)
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func performStream(
        path: String,
        message: String,
        continuation: AsyncStream<ChatDelta>.Continuation
    ) async throws {
        guard api.hasSession else {
            throw SupabaseManagerError.notAuthenticated
        }

        var url = api.baseURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "stream", value: "true")]
        url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let token = api.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // BYOK headers
        let keychain = KeychainManager(service: "com.nebularnews.ios")
        if let key = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("anthropic", forHTTPHeaderField: "x-user-api-provider")
        } else if let key = keychain.get(forKey: KeychainManager.Key.openaiApiKey) {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
            request.setValue("openai", forHTTPHeaderField: "x-user-api-provider")
        }

        let body = ["message": message]
        request.httpBody = try JSONEncoder().encode(body)

        logger.debug("[STREAM] POST \(url.absoluteString)")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        if httpResponse.statusCode >= 400 {
            throw APIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }

        // Parse SSE lines
        for try await line in bytes.lines {
            if Task.isCancelled { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }

            let jsonStr = String(trimmed.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8) else { continue }

            do {
                let event = try JSONDecoder().decode(SSEEvent.self, from: data)
                switch event.type {
                case "delta":
                    if let content = event.content {
                        continuation.yield(.text(content))
                    }
                case "done":
                    let usage = TokenUsage(
                        promptTokens: event.usage?.promptTokens,
                        completionTokens: event.usage?.completionTokens,
                        totalTokens: event.usage?.totalTokens
                    )
                    continuation.yield(.done(content: event.content ?? "", usage: usage))
                case "error":
                    continuation.yield(.error(event.error ?? "Unknown streaming error"))
                default:
                    break
                }
            } catch {
                logger.warning("Failed to decode SSE event: \(jsonStr)")
            }
        }
    }
}

// MARK: - SSE Event

private struct SSEEvent: Decodable {
    let type: String
    var content: String?
    var error: String?
    var usage: SSEUsage?
}

private struct SSEUsage: Decodable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
}
