import Foundation
import SwiftData

public struct ArticleContentFetchCandidate: Sendable {
    public let id: String
    public let canonicalUrl: String
    public let title: String?
    public let currentTextLength: Int
    public let sortDate: Date

    public init(
        id: String,
        canonicalUrl: String,
        title: String?,
        currentTextLength: Int,
        sortDate: Date
    ) {
        self.id = id
        self.canonicalUrl = canonicalUrl
        self.title = title
        self.currentTextLength = currentTextLength
        self.sortDate = sortDate
    }
}

public enum ArticleContentFetchStatus: String, Sendable {
    case fetched
    case skipped
    case blocked
    case failed
}

public struct ArticleContentFetchResult: Sendable {
    public let articleId: String
    public let status: ArticleContentFetchStatus
    public let extractedTextLength: Int?

    public init(
        articleId: String,
        status: ArticleContentFetchStatus,
        extractedTextLength: Int? = nil
    ) {
        self.articleId = articleId
        self.status = status
        self.extractedTextLength = extractedTextLength
    }
}

public protocol ArticlePageFetching: Sendable {
    func fetchHTML(url: String) async throws -> String
}

public struct URLSessionArticlePageFetcher: ArticlePageFetching {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    public func fetchHTML(url: String) async throws -> String {
        guard let url = URL(string: url) else {
            throw FeedFetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (compatible; NebularNews/1.0; +https://nebular.news/article)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedFetchError.networkError(underlying: "Missing HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedFetchError.httpError(statusCode: httpResponse.statusCode)
        }

        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           !contentType.localizedCaseInsensitiveContains("text/html"),
           !contentType.localizedCaseInsensitiveContains("application/xhtml+xml") {
            throw FeedFetchError.networkError(underlying: "Non-HTML response")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw FeedFetchError.networkError(underlying: "Unable to decode HTML")
        }

        return html
    }
}

public actor ArticleContentFetcher {
    private let articleRepo: LocalArticleRepository
    private let pageFetcher: any ArticlePageFetching
    private let minimumCurrentTextLength = 1_200
    private let minimumFetchedTextLength = 900
    private let minimumImprovement = 150
    private let retryAfter: TimeInterval = 3 * 86_400

    public init(
        modelContainer: ModelContainer,
        pageFetcher: (any ArticlePageFetching)? = nil
    ) {
        self.articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        self.pageFetcher = pageFetcher ?? URLSessionArticlePageFetcher()
    }

    public func fetchMissingContent(articleId: String) async -> ArticleContentFetchResult {
        guard let candidate = await articleRepo.contentFetchCandidate(id: articleId) else {
            return ArticleContentFetchResult(articleId: articleId, status: .skipped)
        }

        return await fetch(candidate: candidate)
    }

    public func fetchMissingContentBatch(limit: Int = 5, recentOnly: Bool = true) async -> [ArticleContentFetchResult] {
        let candidates = await articleRepo.listContentFetchCandidates(limit: limit, recentOnly: recentOnly)
        var results: [ArticleContentFetchResult] = []

        for candidate in candidates {
            if Task.isCancelled { break }
            let result = await fetch(candidate: candidate)
            results.append(result)
        }

        return results
    }

    private func fetch(candidate: ArticleContentFetchCandidate) async -> ArticleContentFetchResult {
        do {
            // TODO: When this app becomes a true companion to the NebularNews website,
            // prefer pulling canonical article content from the website/server pipeline
            // before falling back to on-device HTML fetching and extraction.
            let html = try await pageFetcher.fetchHTML(url: candidate.canonicalUrl)

            if ArticleContentExtractor.looksBlocked(html) {
                try? await articleRepo.recordContentFetchAttempt(id: candidate.id)
                return ArticleContentFetchResult(articleId: candidate.id, status: .blocked)
            }

            guard let extracted = ArticleContentExtractor.extractMainContent(from: html) else {
                try? await articleRepo.recordContentFetchAttempt(id: candidate.id)
                return ArticleContentFetchResult(articleId: candidate.id, status: .failed)
            }

            let requiredLength = max(minimumFetchedTextLength, candidate.currentTextLength + minimumImprovement)
            guard extracted.textLength >= requiredLength else {
                try? await articleRepo.recordContentFetchAttempt(id: candidate.id)
                return ArticleContentFetchResult(articleId: candidate.id, status: .failed, extractedTextLength: extracted.textLength)
            }

            try await articleRepo.updateFetchedContent(
                id: candidate.id,
                contentHtml: extracted.contentHtml,
                excerpt: extracted.excerpt
            )

            return ArticleContentFetchResult(
                articleId: candidate.id,
                status: .fetched,
                extractedTextLength: extracted.textLength
            )
        } catch {
            try? await articleRepo.recordContentFetchAttempt(id: candidate.id)
            return ArticleContentFetchResult(articleId: candidate.id, status: .failed)
        }
    }
}

struct ArticleContentExtractor {
    struct Extraction: Sendable {
        let contentHtml: String
        let excerpt: String
        let textLength: Int
    }

    private struct Candidate {
        let paragraphs: [String]
        let textLength: Int
        let score: Int
    }

    private static let blockMarkers = [
        "just a moment...",
        "attention required! | cloudflare",
        "cf-browser-verification",
        "challenge-platform",
        "enable javascript and cookies to continue",
        "__cf_chl_tk",
        "why have i been blocked?"
    ]

    static func looksBlocked(_ html: String) -> Bool {
        let haystack = html.lowercased()
        return blockMarkers.contains { haystack.contains($0) }
    }

    static func extractMainContent(from html: String) -> Extraction? {
        guard !looksBlocked(html) else { return nil }

        let sanitizedHTML = removeNoiseTags(from: html)
        var candidates: [Candidate] = []

        if let articleBody = extractArticleBody(from: sanitizedHTML) {
            candidates.append(articleBody)
        }

        candidates.append(contentsOf: extractSectionCandidates(tag: "article", from: sanitizedHTML))
        candidates.append(contentsOf: extractSectionCandidates(tag: "main", from: sanitizedHTML))
        candidates.append(contentsOf: extractSemanticSectionCandidates(from: sanitizedHTML))

        if let global = extractGlobalParagraphs(from: sanitizedHTML) {
            candidates.append(global)
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return nil
        }

        guard best.textLength > 0 else {
            return nil
        }

        let contentHtml = best.paragraphs
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined(separator: "\n")

        let excerpt = best.paragraphs.joined(separator: " ").truncated(to: 300)

        return Extraction(
            contentHtml: contentHtml,
            excerpt: excerpt,
            textLength: best.textLength
        )
    }

    private static func extractArticleBody(from html: String) -> Candidate? {
        let pattern = #""articleBody"\s*:\s*"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let bodyRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        let literal = String(html[bodyRange])
        let decoded = decodeJSONStringLiteral(literal)?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let paragraphs = decoded?
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 40 }

        return makeCandidate(paragraphs: paragraphs ?? [])
    }

    private static func extractSectionCandidates(tag: String, from html: String) -> [Candidate] {
        let pattern = "(?is)<\\s*\(tag)\\b[^>]*>(.*?)<\\s*/\\s*\(tag)\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let section = String(html[range])
            return makeCandidate(fromSection: section)
        }
    }

    private static func extractSemanticSectionCandidates(from html: String) -> [Candidate] {
        let pattern = #"(?is)<(?:section|div)\b[^>]*(?:itemprop\s*=\s*["']articleBody["']|class\s*=\s*["'][^"']*(?:article|content|entry-content|post-content|story-body)[^"']*["'])[^>]*>(.*?)</(?:section|div)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return makeCandidate(fromSection: String(html[range]))
        }
    }

    private static func extractGlobalParagraphs(from html: String) -> Candidate? {
        makeCandidate(fromSection: html)
    }

    private static func makeCandidate(fromSection html: String) -> Candidate? {
        let paragraphPattern = #"(?is)<p\b[^>]*>(.*?)</p>"#
        let listItemPattern = #"(?is)<li\b[^>]*>(.*?)</li>"#

        var paragraphs = extractTexts(matching: paragraphPattern, in: html)
        let listItems = extractTexts(matching: listItemPattern, in: html).map { "• \($0)" }

        if !listItems.isEmpty {
            paragraphs.append(contentsOf: listItems)
        }

        if paragraphs.isEmpty {
            let fallbackText = html.strippedHTML
            if fallbackText.count >= 200 {
                paragraphs = fallbackText
                    .split(separator: ".")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 50 }
                    .map { $0.hasSuffix(".") ? $0 : "\($0)." }
            }
        }

        return makeCandidate(paragraphs: paragraphs)
    }

    private static func makeCandidate(paragraphs: [String]) -> Candidate? {
        let cleaned = paragraphs
            .map {
                $0
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.count >= 40 }

        guard !cleaned.isEmpty else {
            return nil
        }

        let textLength = cleaned.reduce(0) { $0 + $1.count }
        let score = textLength + (cleaned.count * 120)

        return Candidate(
            paragraphs: Array(cleaned.prefix(60)),
            textLength: textLength,
            score: score
        )
    }

    private static func extractTexts(matching pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let innerHTML = String(html[range])
            let text = innerHTML.strippedHTML
            return text.isEmpty ? nil : text
        }
    }

    private static func removeNoiseTags(from html: String) -> String {
        html
            .replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "(?is)<(script|style|svg|noscript|iframe|form|nav|header|footer|aside)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
    }

    private static func decodeJSONStringLiteral(_ literal: String) -> String? {
        let wrapped = "\"\(literal)\""
        guard let data = wrapped.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
