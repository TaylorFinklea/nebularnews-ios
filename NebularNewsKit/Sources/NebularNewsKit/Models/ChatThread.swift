import Foundation
import SwiftData

/// A conversation thread — either global or scoped to a specific article.
@Model
public final class ChatThread: @unchecked Sendable {
    public var id: String = UUID().uuidString
    public var title: String?
    public var articleId: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    public var messages: [ChatMessage]? = []

    public init(title: String? = nil, articleId: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.articleId = articleId
    }
}

/// A single message within a chat thread.
@Model
public final class ChatMessage: @unchecked Sendable {
    public var id: String = UUID().uuidString
    public var role: String = "user"
    public var content: String = ""
    public var tokenCount: Int?
    public var createdAt: Date = Date()

    public var thread: ChatThread?

    public init(role: String, content: String) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}
