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
        /// Server-executed tool — backend already applied the effect; show a chip.
        case toolServerResult(name: String, summary: String, succeeded: Bool)
        /// Client-executed tool — iOS must dispatch locally.
        case toolClientCall(name: String, args: [String: AnyCodable])
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
                case "tool_call_server":
                    continuation.yield(.toolServerResult(
                        name: event.name ?? "unknown",
                        summary: event.summary ?? event.name ?? "",
                        succeeded: event.succeeded ?? true
                    ))
                case "tool_call_client":
                    continuation.yield(.toolClientCall(
                        name: event.name ?? "unknown",
                        args: event.args ?? [:]
                    ))
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
    // Tool-call fields (M11 — present on tool_call_server / tool_call_client events).
    var name: String?
    var summary: String?
    var succeeded: Bool?
    var args: [String: AnyCodable]?
}

private struct SSEUsage: Decodable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
}

/// Minimal dynamic JSON value for tool-call argument bags.
/// Only supports the primitives the M11 tool parameters actually use.
public enum AnyCodable: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
