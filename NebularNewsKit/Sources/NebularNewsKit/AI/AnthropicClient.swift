import Foundation

// MARK: - Public Types

/// A single message in an Anthropic Messages API conversation.
public struct AIMessage: Sendable, Codable {
    public let role: String  // "user" | "assistant"
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Result of a successful Anthropic API call.
public struct AIResponse: Sendable {
    public let text: String
    public let inputTokens: Int
    public let outputTokens: Int
}

public struct AnthropicModelDescriptor: Sendable, Hashable {
    public let id: String
    public let displayName: String?
    public let createdAt: Date?

    public init(id: String, displayName: String?, createdAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

/// Errors specific to the Anthropic Messages API.
public enum AnthropicError: LocalizedError, Sendable {
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(statusCode: Int, message: String)
    case networkError(underlying: String)
    case parseError(detail: String)
    case noContent

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid API key. Check your Anthropic key in Settings."
        case .rateLimited(let retry):
            let suffix = retry.map { " Retry after \($0)s." } ?? ""
            return "Rate limited by Anthropic.\(suffix)"
        case .serverError(let code, let msg):
            return "Anthropic server error (\(code)): \(msg)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .parseError(let detail):
            return "Failed to parse Anthropic response: \(detail)"
        case .noContent:
            return "Anthropic returned an empty response."
        }
    }
}

// MARK: - Client

/// Stateless, `Sendable` HTTP client for the Anthropic Messages API.
///
/// No third-party SDK — the Messages API is a single POST endpoint:
/// `POST https://api.anthropic.com/v1/messages`
///
/// This struct holds no mutable state; it just wraps URLSession with the
/// correct headers and response parsing.
public struct AnthropicClient: Sendable {
    private let apiKey: String
    private let session: URLSession
    private let messagesURL = "https://api.anthropic.com/v1/messages"
    private let modelsURL = "https://api.anthropic.com/v1/models"
    private let apiVersion = "2023-06-01"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Send a chat completion request to the Anthropic Messages API.
    ///
    /// - Parameters:
    ///   - messages: Conversation messages (user/assistant alternating).
    ///   - system: Optional system prompt.
    ///   - model: Model identifier (e.g. `claude-haiku-4-5-20251001`).
    ///   - maxTokens: Maximum tokens in the response.
    ///   - temperature: Sampling temperature (0.0–1.0).
    /// - Returns: The assistant's text response with token usage.
    public func chat(
        messages: [AIMessage],
        system: String? = nil,
        model: String,
        maxTokens: Int = 1024,
        temperature: Double = 0.0
    ) async throws -> AIResponse {
        // Build request body
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let system {
            body["system"] = system
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        // Build HTTP request
        var request = URLRequest(url: URL(string: messagesURL)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        // Execute
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnthropicError.networkError(underlying: error.localizedDescription)
        }

        // Parse HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.networkError(underlying: "Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200:
            break // success, continue parsing
        case 401:
            throw AnthropicError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap(Int.init)
            throw AnthropicError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse response JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicError.parseError(detail: "Response is not valid JSON")
        }

        // Extract text from content array
        guard let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AnthropicError.noContent
        }

        // Extract usage
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0

        return AIResponse(text: text, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    public func listModels() async throws -> [AnthropicModelDescriptor] {
        var request = URLRequest(url: URL(string: modelsURL)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnthropicError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.networkError(underlying: "Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw AnthropicError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap(Int.init)
            throw AnthropicError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: AnthropicModelListResponse
        do {
            payload = try decoder.decode(AnthropicModelListResponse.self, from: data)
        } catch {
            throw AnthropicError.parseError(detail: error.localizedDescription)
        }

        return payload.data.map {
            AnthropicModelDescriptor(
                id: $0.id,
                displayName: $0.displayName,
                createdAt: $0.createdAt
            )
        }
    }
}

private struct AnthropicModelListResponse: Decodable {
    let data: [AnthropicModelRecord]
}

private struct AnthropicModelRecord: Decodable {
    let id: String
    let displayName: String?
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}
