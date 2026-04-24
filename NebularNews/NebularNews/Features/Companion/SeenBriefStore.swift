import Foundation
import SwiftUI

/// Client-local read state for briefs. Persisted via UserDefaults under the
/// `seenBriefIds` key as a JSON-encoded array of brief ids. Backed by
/// @AppStorage so views observe mutations reactively.
///
/// Cross-device sync is intentionally out of scope — briefs are ephemeral
/// daily content and per-device read state matches user expectation on iOS.
enum SeenBriefStore {
    private static let key = "seenBriefIds"
    private static let maxRetained = 500

    /// Decode the persisted id list. Returns an empty set on any decode error.
    static func load() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    /// Append a brief id, capping the retained list at `maxRetained` (FIFO).
    static func markSeen(_ briefId: String) {
        var ids: [String]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids = decoded
        } else {
            ids = []
        }
        if ids.contains(briefId) { return }
        ids.append(briefId)
        if ids.count > maxRetained {
            ids.removeFirst(ids.count - maxRetained)
        }
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
