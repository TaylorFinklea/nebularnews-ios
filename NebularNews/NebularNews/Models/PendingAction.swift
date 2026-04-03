import Foundation
import SwiftData

@Model
final class PendingAction {
    @Attribute(.unique) var id: String = UUID().uuidString
    var actionType: String      // "read", "save", "reaction", "tag_add", "tag_remove"
    var articleId: String
    var payload: String          // JSON-encoded action data
    var createdAt: Date = Date()
    var retryCount: Int = 0
    var lastError: String?

    init(actionType: String, articleId: String, payload: String) {
        self.actionType = actionType
        self.articleId = articleId
        self.payload = payload
    }
}
