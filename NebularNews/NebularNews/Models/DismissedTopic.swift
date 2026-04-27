import Foundation
import SwiftData

/// Local-only suppression entry. The user dismisses a brief bullet because
/// they don't want to keep seeing the topic; the dismissal lives entirely
/// on-device (privacy by design). When the iOS client requests a new brief,
/// it sends the active suppressions in the request body so the server-side
/// AI can skip matching topics — unless the user opted into resurface on
/// material developments and an article describes one.
///
/// `signature` is a short user-readable topic descriptor ("Iraq war
/// coverage", "Apple OS rumors"). `sourceArticleIds` is captured at
/// dismiss-time so the AI also has anchor candidates for content
/// fingerprinting on subsequent briefs.
@Model
final class DismissedTopic {
    @Attribute(.unique) var id: String
    var signature: String
    var sourceArticleIdsJson: String   // JSON-encoded [String]
    var expiresAt: Date
    var allowResurfaceOnDevelopments: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        signature: String,
        sourceArticleIds: [String],
        expiresAt: Date,
        allowResurfaceOnDevelopments: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.signature = signature
        self.sourceArticleIdsJson = (try? String(data: JSONEncoder().encode(sourceArticleIds), encoding: .utf8)) ?? "[]"
        self.expiresAt = expiresAt
        self.allowResurfaceOnDevelopments = allowResurfaceOnDevelopments
        self.createdAt = createdAt
    }

    var sourceArticleIds: [String] {
        guard
            let data = sourceArticleIdsJson.data(using: .utf8),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }
}
