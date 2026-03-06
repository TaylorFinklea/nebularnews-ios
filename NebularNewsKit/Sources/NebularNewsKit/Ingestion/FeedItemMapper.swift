import Foundation
import CryptoKit
import FeedKit

/// Stateless mapper that converts FeedKit types into our `ParsedArticle` / `ParsedFeedMetadata` structs.
///
/// All methods are pure (no side effects, no state) — ideal for unit testing.
/// Handles three feed formats: RSS 2.0, Atom, and JSON Feed.
public enum FeedItemMapper {

    // MARK: - Feed-Level Metadata

    /// Extract title, site URL, and icon from a parsed feed.
    public static func extractMetadata(from feed: FeedKit.Feed) -> ParsedFeedMetadata {
        switch feed {
        case .rss(let rss):
            return ParsedFeedMetadata(
                title: rss.title,
                siteUrl: rss.link,
                iconUrl: rss.image?.url
            )
        case .atom(let atom):
            let siteUrl = atom.links?.first(where: { $0.attributes?.rel == "alternate" })?.attributes?.href
                ?? atom.links?.first?.attributes?.href
            return ParsedFeedMetadata(
                title: atom.title,
                siteUrl: siteUrl,
                iconUrl: atom.icon
            )
        case .json(let json):
            return ParsedFeedMetadata(
                title: json.title,
                siteUrl: json.homePageURL,
                iconUrl: json.favicon ?? json.icon
            )
        }
    }

    // MARK: - Article Extraction

    /// Extract all items from a feed as `ParsedArticle` structs.
    ///
    /// Items missing both a URL and a title are skipped — they're not useful
    /// for display and can't be reliably deduped.
    public static func extractArticles(from feed: FeedKit.Feed) -> [ParsedArticle] {
        switch feed {
        case .rss(let rss):
            return (rss.items ?? []).compactMap(mapRSSItem)
        case .atom(let atom):
            return (atom.entries ?? []).compactMap(mapAtomEntry)
        case .json(let json):
            return (json.items ?? []).compactMap(mapJSONItem)
        }
    }

    // MARK: - RSS

    private static func mapRSSItem(_ item: RSSFeedItem) -> ParsedArticle? {
        let url = item.link
        let title = item.title

        // Skip items with neither URL nor title
        guard url != nil || title != nil else { return nil }

        // Prefer content:encoded (richer HTML) over description
        let contentHtml = item.content?.contentEncoded ?? item.description
        // Use description as excerpt (it's usually a summary in RSS)
        let excerpt = item.description.map(stripHTML)

        // Extract image from enclosure or media namespace
        let imageUrl = item.enclosure?.attributes?.url
            ?? item.media?.mediaThumbnails?.first?.attributes?.url

        return ParsedArticle(
            url: url,
            title: title,
            author: item.author ?? item.dublinCore?.dcCreator,
            publishedAt: item.pubDate,
            contentHtml: contentHtml,
            excerpt: excerpt.map { String($0.prefix(300)) },
            imageUrl: imageUrl,
            contentHash: computeHash(url: url, title: title, publishedAt: item.pubDate)
        )
    }

    // MARK: - Atom

    private static func mapAtomEntry(_ entry: AtomFeedEntry) -> ParsedArticle? {
        // Canonical URL: prefer alternate link, fall back to first link
        let url = entry.links?.first(where: { $0.attributes?.rel == "alternate" })?.attributes?.href
            ?? entry.links?.first?.attributes?.href
        let title = entry.title

        guard url != nil || title != nil else { return nil }

        let contentHtml = entry.content?.value
        let excerpt = (entry.summary?.value).map(stripHTML)

        // Image from media namespace
        let imageUrl = entry.media?.mediaThumbnails?.first?.attributes?.url

        return ParsedArticle(
            url: url,
            title: title,
            author: entry.authors?.first?.name,
            publishedAt: entry.published ?? entry.updated,
            contentHtml: contentHtml,
            excerpt: excerpt.map { String($0.prefix(300)) },
            imageUrl: imageUrl,
            contentHash: computeHash(url: url, title: title, publishedAt: entry.published ?? entry.updated)
        )
    }

    // MARK: - JSON Feed

    private static func mapJSONItem(_ item: JSONFeedItem) -> ParsedArticle? {
        let url = item.url
        let title = item.title

        guard url != nil || title != nil else { return nil }

        let contentHtml = item.contentHtml
        let excerpt = (item.summary ?? item.contentText).map { String($0.prefix(300)) }

        return ParsedArticle(
            url: url,
            title: title,
            author: item.author?.name,
            publishedAt: item.datePublished,
            contentHtml: contentHtml,
            excerpt: excerpt,
            imageUrl: item.image ?? item.bannerImage,
            contentHash: computeHash(url: url, title: title, publishedAt: item.datePublished)
        )
    }

    // MARK: - Hashing

    /// Compute a content hash for deduplication.
    ///
    /// Priority: URL (most stable) → title + date → title alone.
    /// Uses SHA256 truncated to 16 hex chars for compactness.
    public static func computeHash(url: String?, title: String?, publishedAt: Date?) -> String {
        let input: String
        if let url, !url.isEmpty {
            input = url
        } else if let title, !title.isEmpty, let date = publishedAt {
            input = "\(title)|\(date.timeIntervalSince1970)"
        } else if let title, !title.isEmpty {
            input = title
        } else {
            input = UUID().uuidString // Last resort — won't dedup but won't crash
        }

        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - HTML Helpers

    /// Crude HTML tag stripper for generating plain-text excerpts.
    /// Good enough for summaries — full rendering uses WKWebView.
    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
