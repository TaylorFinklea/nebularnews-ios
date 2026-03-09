import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

private struct MockArticlePageFetcher: ArticlePageFetching, @unchecked Sendable {
    var htmlByURL: [String: String] = [:]

    func fetchHTML(url: String) async throws -> String {
        guard let html = htmlByURL[url] else {
            throw FeedFetchError.invalidURL
        }
        return html
    }
}

@Suite("ArticleContentFetcher")
struct ArticleContentFetcherTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeLongArticleHTML(title: String = "Example") -> String {
        let paragraphs = (1...10).map { index in
            """
            <p>\(title) paragraph \(index) explains the article in detail with enough words to look like real body copy and provide meaningful extraction for testing the local full-text pipeline.</p>
            """
        }.joined(separator: "\n")

        return """
        <html>
          <body>
            <header><p>Navigation text</p></header>
            <article>
              \(paragraphs)
            </article>
            <footer><p>Footer text</p></footer>
          </body>
        </html>
        """
    }

    @Test("Fetches canonical article text for thin feed items")
    func fetchesCanonicalArticleText() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)
        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Example Feed")

        let parsed = ParsedArticle(
            url: "https://example.com/post",
            title: "Thin Article",
            excerpt: "Short summary only.",
            contentHash: "thin-article"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: parsed)

        let insertedArticles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 10, offset: 0)
        let article = try #require(insertedArticles.first)
        article.summaryText = "Old summary"
        article.keyPointsJson = "[\"old\"]"
        article.score = 3
        article.personalizationVersion = currentPersonalizationVersion

        let fetcher = ArticleContentFetcher(
            modelContainer: container,
            pageFetcher: MockArticlePageFetcher(
                htmlByURL: ["https://example.com/post": makeLongArticleHTML()]
            )
        )

        let result = await fetcher.fetchMissingContent(articleId: article.id)

        #expect(result.status == .fetched)

        let verificationRepo = LocalArticleRepository(modelContainer: container)
        let refreshedArticle = await verificationRepo.get(id: article.id)
        let refreshed = try #require(refreshedArticle)
        #expect(refreshed.contentFetchedAt != nil)
        #expect(refreshed.contentHtml?.contains("<p>") == true)
        #expect(refreshed.bestAvailableContentLength >= 900)
        #expect(refreshed.summaryText == nil)
        #expect(refreshed.keyPoints.isEmpty)
        #expect(refreshed.score == nil)
        #expect(refreshed.personalizationVersion == 0)
    }

    @Test("Blocked challenge pages record one failed attempt")
    func recordsBlockedAttempt() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)
        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Example Feed")

        let parsed = ParsedArticle(
            url: "https://example.com/blocked",
            title: "Blocked Article",
            contentHash: "blocked-article"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: parsed)

        let insertedArticles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 10, offset: 0)
        let article = try #require(insertedArticles.first)
        let fetcher = ArticleContentFetcher(
            modelContainer: container,
            pageFetcher: MockArticlePageFetcher(
                htmlByURL: ["https://example.com/blocked": "<html><title>Just a moment...</title><body>Enable JavaScript and cookies to continue</body></html>"]
            )
        )

        let result = await fetcher.fetchMissingContent(articleId: article.id)

        #expect(result.status == .blocked)

        let verificationRepo = LocalArticleRepository(modelContainer: container)
        let refreshedArticle = await verificationRepo.get(id: article.id)
        let refreshed = try #require(refreshedArticle)
        #expect(refreshed.contentFetchAttemptedAt != nil)
        #expect(refreshed.contentFetchedAt == nil)
        #expect(refreshed.contentHtml == nil)
    }

    @Test("Recently attempted articles are skipped until retry window passes")
    func skipsRecentlyAttemptedArticles() async throws {
        let container = try makeContainer()
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)
        let feed = try await feedRepo.add(feedUrl: "https://example.com/feed.xml", title: "Example Feed")

        let parsed = ParsedArticle(
            url: "https://example.com/retry",
            title: "Retry Article",
            excerpt: "Still thin.",
            contentHash: "retry-article"
        )
        try await articleRepo.insertForFeed(feedId: feed.id, article: parsed)

        let insertedArticles = await articleRepo.list(filter: ArticleFilter(), sort: .newest, limit: 10, offset: 0)
        let article = try #require(insertedArticles.first)
        article.contentFetchAttemptedAt = Date()

        let skippedCandidate = await articleRepo.contentFetchCandidate(id: article.id)
        #expect(skippedCandidate == nil)

        article.contentFetchAttemptedAt = Date(timeIntervalSinceNow: -4 * 86_400)
        let retriedCandidate = await articleRepo.contentFetchCandidate(id: article.id)
        #expect(retriedCandidate?.id == article.id)
    }
}
