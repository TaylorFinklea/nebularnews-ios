import Foundation

struct FeedURLNormalized {
    let url: String
    let scrapeMode: String?
    let sourceLabel: String?
}

/// Converts pasted source URLs into their RSS/Atom equivalents.
///
/// Handles Reddit, YouTube, Mastodon, and HackerNews. All other URLs pass
/// through unchanged. scrapeMode is set to "auto_fetch_on_empty" for sources
/// (Reddit, HN) that link to external articles rather than inline content.
struct FeedURLNormalizer {

    static func normalize(_ raw: String) -> FeedURLNormalized {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else {
            return FeedURLNormalized(url: trimmed, scrapeMode: nil, sourceLabel: nil)
        }

        let host = components.host ?? ""
        let path = components.path

        // Reddit subreddit — posts link to external sites
        if host == "reddit.com" || host == "www.reddit.com" {
            if let subredditName = redditSubredditName(from: path) {
                let rssURL = "https://www.reddit.com/r/\(subredditName)/.rss"
                return FeedURLNormalized(url: rssURL, scrapeMode: "auto_fetch_on_empty", sourceLabel: "Subreddit – will fetch full posts")
            }
        }

        // YouTube channel or handle
        if host == "youtube.com" || host == "www.youtube.com" {
            if path.hasPrefix("/@") {
                // @handles need a channel_id to generate a valid RSS URL, which
                // requires a network lookup. Pass through so the feed validator
                // surfaces a clear error rather than silently subscribing to a broken feed.
                let handle = String(path.dropFirst(2)).components(separatedBy: "/").first ?? ""
                return FeedURLNormalized(url: "https://www.youtube.com/@\(handle)", scrapeMode: nil, sourceLabel: "YouTube – paste the channel RSS URL instead (youtube.com/feeds/videos.xml?channel_id=…)")
            }
            if path.hasPrefix("/channel/") {
                let channelId = String(path.dropFirst("/channel/".count)).components(separatedBy: "/").first ?? ""
                if !channelId.isEmpty {
                    let rssURL = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelId)"
                    return FeedURLNormalized(url: rssURL, scrapeMode: nil, sourceLabel: "YouTube Channel")
                }
            }
        }

        // Mastodon profile (@handle at end of path, not followed by subpath)
        let mastodonPattern = #"^/@[^/]+$"#
        if path.range(of: mastodonPattern, options: .regularExpression) != nil {
            let base = "\(components.scheme ?? "https")://\(host)\(path)"
            let rssURL = base.hasSuffix(".rss") ? base : "\(base).rss"
            return FeedURLNormalized(url: rssURL, scrapeMode: nil, sourceLabel: "Mastodon Account")
        }

        // Hacker News front page
        if host == "news.ycombinator.com" && (path == "/" || path.isEmpty) {
            return FeedURLNormalized(url: "https://hnrss.org/frontpage", scrapeMode: "auto_fetch_on_empty", sourceLabel: "Hacker News – will fetch full articles")
        }

        return FeedURLNormalized(url: trimmed, scrapeMode: nil, sourceLabel: nil)
    }

    private static func redditSubredditName(from path: String) -> String? {
        let pattern = #"^/r/([^/]+)"#
        guard let match = path.range(of: pattern, options: .regularExpression) else { return nil }
        let subredditPath = String(path[match])
        let name = String(subredditPath.dropFirst(3)) // drop /r/
        return name.isEmpty ? nil : name
    }
}
