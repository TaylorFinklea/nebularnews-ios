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
        /// `undo` carries the inverse tool name + JSON args (base64-encoded) when
        /// the mutation is reversible.
        case toolServerResult(name: String, summary: String, succeeded: Bool, undoTool: String?, undoArgsB64: String?)
        /// Client-executed tool — iOS must dispatch locally.
        case toolClientCall(name: String, args: [String: AnyCodable])
        /// Server requires user confirmation before executing the tool.
        case toolProposal(
            proposeId: String,
            name: String,
            args: [String: AnyCodable],
            summary: String,
            detail: ToolProposalDetail,
            contextHint: String?
        )
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
        threadId: String?,
        guardrailPolicies: [String: String]? = nil
    ) -> AsyncStream<ChatDelta> {
        streamAssistantChat(message: content, pageContext: pageContext, threadId: threadId, guardrailPolicies: guardrailPolicies)
    }

    /// Resume a conversation after the user approves or rejects a tool proposal.
    func streamConfirmTool(
        proposeId: String,
        decision: String,
        edits: [String: AnyCodable]? = nil
    ) -> AsyncStream<ChatDelta> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performConfirmToolStream(
                        proposeId: proposeId,
                        decision: decision,
                        edits: edits,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func streamAssistantChat(
        message: String,
        pageContext: AIPageContext,
        threadId: String?,
        guardrailPolicies: [String: String]? = nil
    ) -> AsyncStream<ChatDelta> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await performAssistantStream(
                        message: message,
                        pageContext: pageContext,
                        threadId: threadId,
                        guardrailPolicies: guardrailPolicies,
                        continuation: continuation
                    )
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
        guardrailPolicies: [String: String]? = nil,
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
            let guardrails: Guardrails?
            struct Guardrails: Encodable {
                let policies: [String: String]
            }
        }

        let guardrailsPayload = guardrailPolicies.map { AssistantBody.Guardrails(policies: $0) }
        request.httpBody = try JSONEncoder().encode(
            AssistantBody(message: message, pageContext: pageContext, threadId: threadId, guardrails: guardrailsPayload)
        )

        logger.debug("[STREAM] POST \(url.absoluteString)")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        if httpResponse.statusCode >= 400 {
            // Drain the body — backend emits a JSON envelope with the real error.
            var bodyText = ""
            for try await line in bytes.lines { bodyText += line }
            struct ErrShape: Decodable { struct E: Decodable { let message: String? }; let error: E? }
            if let data = bodyText.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(ErrShape.self, from: data),
               let msg = parsed.error?.message, !msg.isEmpty {
                throw APIError.serverError(httpResponse.statusCode, msg)
            }
            throw APIError.serverError(httpResponse.statusCode, bodyText.isEmpty ? "HTTP \(httpResponse.statusCode)" : bodyText)
        }

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
                    let undoTool = event.undo?.tool
                    // Encode undo args as JSON → base64 so we can round-trip verbatim
                    // when the user taps Undo (POST /chat/undo-tool with the same bag).
                    var undoArgsB64: String? = nil
                    if let undoArgs = event.undo?.args,
                       let data = try? JSONEncoder().encode(undoArgs) {
                        undoArgsB64 = data.base64EncodedString()
                    }
                    continuation.yield(.toolServerResult(
                        name: event.name ?? "unknown",
                        summary: event.summary ?? event.name ?? "",
                        succeeded: event.succeeded ?? true,
                        undoTool: undoTool,
                        undoArgsB64: undoArgsB64
                    ))
                case "tool_call_client":
                    continuation.yield(.toolClientCall(
                        name: event.name ?? "unknown",
                        args: event.args ?? [:]
                    ))
                case "tool_call_propose":
                    if let proposeId = event.proposeId,
                       let name = event.name,
                       let summary = event.summary,
                       let detail = event.detail {
                        continuation.yield(.toolProposal(
                            proposeId: proposeId,
                            name: name,
                            args: event.args ?? [:],
                            summary: summary,
                            detail: detail,
                            contextHint: event.contextHint
                        ))
                    }
                default: break
                }
            } catch {
                logger.warning("Failed to decode SSE: \(jsonStr)")
            }
        }
    }

    private func performConfirmToolStream(
        proposeId: String,
        decision: String,
        edits: [String: AnyCodable]?,
        continuation: AsyncStream<ChatDelta>.Continuation
    ) async throws {
        guard api.hasSession else { throw SupabaseManagerError.notAuthenticated }

        var url = api.baseURL.appendingPathComponent("api/chat/confirm-tool")
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

        struct ConfirmBody: Encodable {
            let proposeId: String
            let decision: String
            let edits: [String: AnyCodable]?
        }

        request.httpBody = try JSONEncoder().encode(ConfirmBody(proposeId: proposeId, decision: decision, edits: edits))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 401 { throw APIError.unauthorized }
        if httpResponse.statusCode == 410 {
            // Proposal expired.
            continuation.yield(.error("proposal_expired"))
            return
        }
        if httpResponse.statusCode >= 400 {
            var bodyText = ""
            for try await line in bytes.lines { bodyText += line }
            throw APIError.serverError(httpResponse.statusCode, bodyText.isEmpty ? "HTTP \(httpResponse.statusCode)" : bodyText)
        }

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
                    let undoTool = event.undo?.tool
                    var undoArgsB64: String? = nil
                    if let undoArgs = event.undo?.args,
                       let argData = try? JSONEncoder().encode(undoArgs) {
                        undoArgsB64 = argData.base64EncodedString()
                    }
                    continuation.yield(.toolServerResult(
                        name: event.name ?? "unknown",
                        summary: event.summary ?? event.name ?? "",
                        succeeded: event.succeeded ?? true,
                        undoTool: undoTool,
                        undoArgsB64: undoArgsB64
                    ))
                case "tool_call_client":
                    continuation.yield(.toolClientCall(name: event.name ?? "unknown", args: event.args ?? [:]))
                case "tool_call_propose":
                    if let proposeId = event.proposeId,
                       let name = event.name,
                       let summary = event.summary,
                       let detail = event.detail {
                        continuation.yield(.toolProposal(
                            proposeId: proposeId,
                            name: name,
                            args: event.args ?? [:],
                            summary: summary,
                            detail: detail,
                            contextHint: event.contextHint
                        ))
                    }
                default: break
                }
            } catch {
                logger.warning("Failed to decode confirm-tool SSE: \(jsonStr)")
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
    var undo: SSEUndoPayload?
    // Proposal fields (M11 guardrails — present on tool_call_propose events).
    var proposeId: String?
    var detail: ToolProposalDetail?
    var contextHint: String?
}

struct SSEUndoPayload: Decodable, Sendable {
    let tool: String
    let args: [String: AnyCodable]
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

// MARK: - Tool Proposal Detail

/// Structured detail payload for the confirmation sheet, discriminated by `kind`.
public enum ToolProposalDetail: Sendable {
    case markArticlesRead(count: Int, previews: [ArticlePreview], remainingCount: Int, feedBreakdown: [FeedCount])
    case pauseFeed(feedId: String, feedTitle: String?, currentArticleCount24h: Int, currentlyPaused: Bool)
    case unsubscribeFromFeed(feedId: String, feedTitle: String?, subscribedAt: Int?, totalArticlesEver: Int, currentlyPaused: Bool)
    case setFeedMaxPerDay(feedId: String, feedTitle: String?, currentCap: Int?, proposedCap: Int, avgArticlesPerDay: Int)
    case setFeedMinScore(feedId: String, feedTitle: String?, currentMinScore: Int?, proposedMinScore: Int, currentScoreDistribution: ScoreDistribution)
    case unknown

    public struct ArticlePreview: Sendable {
        public let id: String
        public let title: String
        public let feedTitle: String?
    }
    public struct FeedCount: Sendable {
        public let feedTitle: String
        public let n: Int
    }
    public struct ScoreDistribution: Sendable {
        public let p25: Int
        public let p50: Int
        public let p75: Int
    }
}

extension ToolProposalDetail: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, count, previews, remainingCount, feedBreakdown
        case feedId, feedTitle, currentArticleCount24h, currentlyPaused
        case subscribedAt, totalArticlesEver
        case currentCap, proposedCap, avgArticlesPerDay
        case currentMinScore, proposedMinScore, currentScoreDistribution
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        switch kind {
        case "mark_articles_read":
            struct Preview: Decodable { let id: String; let title: String; let feedTitle: String? }
            struct FC: Decodable { let feedTitle: String; let n: Int }
            let count = (try? container.decode(Int.self, forKey: .count)) ?? 0
            let rawPreviews = (try? container.decode([Preview].self, forKey: .previews)) ?? []
            let remaining = (try? container.decode(Int.self, forKey: .remainingCount)) ?? 0
            let rawBreakdown = (try? container.decode([FC].self, forKey: .feedBreakdown)) ?? []
            self = .markArticlesRead(
                count: count,
                previews: rawPreviews.map { .init(id: $0.id, title: $0.title, feedTitle: $0.feedTitle) },
                remainingCount: remaining,
                feedBreakdown: rawBreakdown.map { .init(feedTitle: $0.feedTitle, n: $0.n) }
            )
        case "pause_feed":
            self = .pauseFeed(
                feedId: (try? container.decode(String.self, forKey: .feedId)) ?? "",
                feedTitle: try? container.decode(String.self, forKey: .feedTitle),
                currentArticleCount24h: (try? container.decode(Int.self, forKey: .currentArticleCount24h)) ?? 0,
                currentlyPaused: (try? container.decode(Bool.self, forKey: .currentlyPaused)) ?? false
            )
        case "unsubscribe_from_feed":
            self = .unsubscribeFromFeed(
                feedId: (try? container.decode(String.self, forKey: .feedId)) ?? "",
                feedTitle: try? container.decode(String.self, forKey: .feedTitle),
                subscribedAt: try? container.decode(Int.self, forKey: .subscribedAt),
                totalArticlesEver: (try? container.decode(Int.self, forKey: .totalArticlesEver)) ?? 0,
                currentlyPaused: (try? container.decode(Bool.self, forKey: .currentlyPaused)) ?? false
            )
        case "set_feed_max_per_day":
            self = .setFeedMaxPerDay(
                feedId: (try? container.decode(String.self, forKey: .feedId)) ?? "",
                feedTitle: try? container.decode(String.self, forKey: .feedTitle),
                currentCap: try? container.decode(Int.self, forKey: .currentCap),
                proposedCap: (try? container.decode(Int.self, forKey: .proposedCap)) ?? 0,
                avgArticlesPerDay: (try? container.decode(Int.self, forKey: .avgArticlesPerDay)) ?? 0
            )
        case "set_feed_min_score":
            struct Dist: Decodable { let p25: Int; let p50: Int; let p75: Int }
            let dist = (try? container.decode(Dist.self, forKey: .currentScoreDistribution)) ?? Dist(p25: 0, p50: 0, p75: 0)
            self = .setFeedMinScore(
                feedId: (try? container.decode(String.self, forKey: .feedId)) ?? "",
                feedTitle: try? container.decode(String.self, forKey: .feedTitle),
                currentMinScore: try? container.decode(Int.self, forKey: .currentMinScore),
                proposedMinScore: (try? container.decode(Int.self, forKey: .proposedMinScore)) ?? 0,
                currentScoreDistribution: .init(p25: dist.p25, p50: dist.p50, p75: dist.p75)
            )
        default:
            self = .unknown
        }
    }
}
