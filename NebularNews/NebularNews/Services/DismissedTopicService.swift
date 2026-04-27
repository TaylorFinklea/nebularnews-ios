import Foundation
import SwiftData

/// Encapsulates queries against the `DismissedTopic` SwiftData store and
/// produces request payloads for the brief generation endpoint.
///
/// Active filtering happens here so callers don't have to remember to drop
/// expired rows. `cleanup()` is idempotent and is intended to run on app
/// foreground so the store doesn't grow unbounded.
@MainActor
final class DismissedTopicService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// All currently-active suppressions (expiresAt in the future).
    func active(now: Date = Date()) -> [DismissedTopic] {
        let descriptor = FetchDescriptor<DismissedTopic>(
            predicate: #Predicate { $0.expiresAt > now },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All suppressions, including expired (used by Settings → manage screen
    /// when we eventually ship one).
    func all() -> [DismissedTopic] {
        let descriptor = FetchDescriptor<DismissedTopic>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Insert a new suppression. Caller specifies duration in days; expiresAt
    /// is computed from `now`. No de-duplication — each dismissal is its own
    /// row, since the AI prompt collapses overlapping signatures naturally.
    @discardableResult
    func add(
        signature: String,
        sourceArticleIds: [String],
        durationDays: Int,
        allowResurfaceOnDevelopments: Bool = true
    ) -> DismissedTopic {
        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: durationDays, to: now) ?? now.addingTimeInterval(TimeInterval(durationDays) * 86_400)
        let topic = DismissedTopic(
            signature: signature,
            sourceArticleIds: sourceArticleIds,
            expiresAt: expires,
            allowResurfaceOnDevelopments: allowResurfaceOnDevelopments,
            createdAt: now
        )
        context.insert(topic)
        try? context.save()
        return topic
    }

    /// Undo a single dismissal — used by the in-line "undo" chip after the
    /// user taps Dismiss in the brief.
    func remove(id: String) {
        let descriptor = FetchDescriptor<DismissedTopic>(predicate: #Predicate { $0.id == id })
        if let match = try? context.fetch(descriptor).first {
            context.delete(match)
            try? context.save()
        }
    }

    /// Drop expired rows. Cheap; runs from `.onAppear` on the Today tab.
    func cleanup(now: Date = Date()) {
        let descriptor = FetchDescriptor<DismissedTopic>(
            predicate: #Predicate { $0.expiresAt <= now }
        )
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return }
        for row in expired { context.delete(row) }
        try? context.save()
    }

    /// Builds the `suppressed_topics[]` array for the brief generation
    /// request body. Returns `nil` when empty so callers can omit the field
    /// entirely (keeps the request shape clean for users with no dismissals).
    func payloadForBriefRequest(now: Date = Date()) -> [SuppressedTopicPayload]? {
        let topics = active(now: now)
        guard !topics.isEmpty else { return nil }
        return topics.map { topic in
            SuppressedTopicPayload(
                signature: topic.signature,
                expires_at: Int(topic.expiresAt.timeIntervalSince1970 * 1000),
                allow_resurface_on_developments: topic.allowResurfaceOnDevelopments
            )
        }
    }
}

/// Wire-format DTO for the suppressed_topics field on POST /brief/generate
/// and POST /admin/briefs/generate-for-user. Snake-case keys match the
/// server contract (the iOS APIClient uses `.convertFromSnakeCase` only for
/// decoding; encoding goes through directly so we mirror the keys here).
struct SuppressedTopicPayload: Codable {
    let signature: String
    let expires_at: Int
    let allow_resurface_on_developments: Bool
}
