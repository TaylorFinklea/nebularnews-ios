import Foundation

/// Decodes the JSON content of a `brief_seed` chat message into a strongly
/// typed structure for the briefing UI.
///
/// The backend writes both the iOS-style enriched format (from `/brief/generate`,
/// where each bullet has a `sources` array with title/url) and the raw cron
/// format (just `source_article_ids`). This decoder accepts both shapes.
struct SeededBrief: Decodable {
    let briefId: String
    let editionKind: String         // 'morning' | 'evening' | 'ondemand'
    let editionSlot: String?
    let generatedAt: Int?
    let windowStart: Int?
    let windowEnd: Int?
    let bullets: [Bullet]
    let sourceArticleIds: [String]?

    struct Bullet: Decodable, Identifiable {
        let text: String
        let sources: [Source]

        var id: String { text }

        struct Source: Decodable, Identifiable {
            let articleId: String
            let title: String?
            let canonicalUrl: String?
            var id: String { articleId }
        }

        // Custom init handles both shapes:
        //   { text, sources: [{article_id, title, canonical_url}] }   (enriched)
        //   { text, source_article_ids: [<id>...] }                    (cron raw)
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.text = try c.decode(String.self, forKey: .text)
            if let enriched = try? c.decode([Source].self, forKey: .sources) {
                self.sources = enriched
            } else if let ids = try? c.decode([String].self, forKey: .sourceArticleIds) {
                self.sources = ids.map { Source(articleId: $0, title: nil, canonicalUrl: nil) }
            } else {
                self.sources = []
            }
        }

        enum CodingKeys: String, CodingKey {
            case text
            case sources
            case sourceArticleIds = "source_article_ids"
        }
    }

    enum CodingKeys: String, CodingKey {
        case briefId = "brief_id"
        case editionKind = "edition_kind"
        case editionSlot = "edition_slot"
        case generatedAt = "generated_at"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case bullets
        case sourceArticleIds = "source_article_ids"
    }

    /// Decodes a brief_seed chat message's `content` field. Returns nil on
    /// any parse failure so the caller can fall back to plain-text rendering.
    static func parse(content: String) -> SeededBrief? {
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SeededBrief.self, from: data)
    }

    /// Aggregated source article IDs across every bullet. Used for batch
    /// actions like "save all" or for the `react_to_articles` tool call
    /// that reacts to all of a bullet's sources at once.
    var allSourceArticleIds: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for b in bullets {
            for s in b.sources where !seen.contains(s.articleId) {
                seen.insert(s.articleId)
                result.append(s.articleId)
            }
        }
        return result
    }

    var displayTitle: String {
        switch editionKind {
        case "morning": return "Morning Brief"
        case "evening": return "Evening Brief"
        case "ondemand": return "News Brief"
        default: return "News Brief"
        }
    }
}
