import Foundation
import SwiftData

/// Fetches Open Graph images from article canonical URLs as a fallback
/// when the RSS feed doesn't provide an image.
///
/// Only downloads the first ~16KB of each page (the HEAD section) to
/// extract `og:image` meta tags efficiently. Results are cached on the
/// Article model so each URL is fetched at most once.
public actor OGImageFetcher {
    private let modelContainer: ModelContainer
    private let session: URLSession

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    /// Fetch the og:image for a single article. Returns the image URL if found.
    public func fetchOGImage(articleId: String, canonicalUrl: String) async -> String? {
        guard let url = URL(string: canonicalUrl) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("bytes=0-16383", forHTTPHeaderField: "Range")
        request.setValue(
            "Mozilla/5.0 (compatible; NebularNews/1.0)",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8)
        else { return nil }

        guard let imageUrl = parseOGImage(from: html) else { return nil }

        let repo = LocalArticleRepository(modelContainer: modelContainer)
        try? await repo.updateOGImageUrl(id: articleId, ogImageUrl: imageUrl)

        return imageUrl
    }

    // MARK: - Private

    private static let ogPattern = try! NSRegularExpression(
        pattern: #"<meta\s+[^>]*property\s*=\s*["']og:image["'][^>]*content\s*=\s*["']([^"']+)["']"#,
        options: .caseInsensitive
    )

    private static let ogPatternReversed = try! NSRegularExpression(
        pattern: #"<meta\s+[^>]*content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']og:image["']"#,
        options: .caseInsensitive
    )

    private func parseOGImage(from html: String) -> String? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for pattern in [Self.ogPattern, Self.ogPatternReversed] {
            if let match = pattern.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                let urlString = String(html[urlRange])
                if urlString.hasPrefix("http") {
                    return urlString
                }
            }
        }

        return nil
    }
}
