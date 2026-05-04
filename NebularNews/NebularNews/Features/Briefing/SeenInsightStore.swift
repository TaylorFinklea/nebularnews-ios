import Foundation

/// Client-local dismissal state for the weekly Reading Insights card.
/// Mirrors SeenBriefStore's UserDefaults pattern but keys by the
/// insight's `generated_at` epoch ms — server caches one snapshot per
/// user per week, so once that timestamp is in the dismissed set the
/// card stays hidden for that week. The next weekly refresh produces a
/// new `generated_at`, which won't be in the set, so the card
/// automatically re-appears.
enum SeenInsightStore {
    private static let key = "seenInsightGeneratedAt"
    /// Roughly a year of weekly insights — bounded growth without ever
    /// realistically clipping legitimate dismissals.
    private static let maxRetained = 60

    static func contains(_ generatedAt: Int) -> Bool {
        load().contains(generatedAt)
    }

    static func markSeen(_ generatedAt: Int) {
        var ids = loadList()
        if ids.contains(generatedAt) { return }
        ids.append(generatedAt)
        if ids.count > maxRetained {
            ids.removeFirst(ids.count - maxRetained)
        }
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load() -> Set<Int> {
        Set(loadList())
    }

    private static func loadList() -> [Int] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return ids
    }
}
