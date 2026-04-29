import Foundation

// MARK: - Feed Settings ETag Helper

/// Mirrors the server's `subscriptionEtag()` in
/// `nebularnews/src/routes/feeds.ts:147` — DO NOT diverge.
///
/// Format: `p<0|1>m<int|empty>n<int|empty>`
/// Examples: `p0m100n3`, `p1mn` (nulls render as empty string)
enum FeedSettingsETag {
    /// Compute the ETag for a set of subscription settings.
    ///
    /// - Parameters:
    ///   - paused: Whether the feed is paused. `true` → "1", `false` → "0".
    ///   - maxArticlesPerDay: Daily article cap. `nil` → empty string.
    ///   - minScore: Minimum score filter. `nil` → empty string; `0` is a real value.
    static func compute(paused: Bool, maxArticlesPerDay: Int?, minScore: Int?) -> String {
        let p = paused ? "1" : "0"
        let m = maxArticlesPerDay.map(String.init) ?? ""
        let n = minScore.map(String.init) ?? ""
        return "p\(p)m\(m)n\(n)"
    }
}
