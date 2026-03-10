import Foundation
import Testing
import SwiftData
@testable import NebularNewsKit

@Suite("ArticleFallbackImageService")
struct ArticleFallbackImageServiceTests {
    private func makeContainer() throws -> ModelContainer {
        try makeInMemoryModelContainer()
    }

    private func makeContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    @discardableResult
    private func insertFeed(in context: ModelContext, title: String) throws -> Feed {
        let feed = Feed(feedUrl: "https://example.com/feed.xml", title: title)
        context.insert(feed)
        try context.save()
        return feed
    }

    @discardableResult
    private func insertArticle(in context: ModelContext, feed: Feed, title: String, content: String) throws -> Article {
        let article = Article(canonicalUrl: "https://example.com/article", title: title)
        article.feed = feed
        article.contentHtml = content
        article.contentHash = UUID().uuidString
        article.contentRevision = 1
        article.contentPreparationStatusRaw = ArticlePreparationStageStatus.skipped.rawValue
        article.imagePreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        article.enrichmentPreparationStatusRaw = ArticlePreparationStageStatus.pending.rawValue
        context.insert(article)
        try context.save()
        return article
    }

    @Test("Live Unsplash search persists a searched fallback image when a key is present")
    func liveUnsplashSearchPersistsResult() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Kubernetes Blog")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Ingress changes in Kubernetes",
            content: String(repeating: "Kubernetes ingress cloud infrastructure article. ", count: 80)
        )
        let tag = Tag(name: "Kubernetes")
        article.tags = [tag]
        context.insert(tag)
        try context.save()

        let keychainService = "test.unsplash.\(UUID().uuidString)"
        let keychain = KeychainManager(service: keychainService)
        try keychain.set("unsplash-test-key", forKey: KeychainManager.Key.unsplashAccessKey)
        defer { keychain.delete(forKey: KeychainManager.Key.unsplashAccessKey) }

        MockUnsplashURLProtocol.handler = { request in
            if request.url?.path == "/search/photos" {
                let body = """
                {
                  "results": [
                    {
                      "urls": {
                        "regular": "https://images.unsplash.com/photo-live-search"
                      },
                      "user": {
                        "name": "Taylor Lens",
                        "links": {
                          "html": "https://unsplash.com/@taylens"
                        }
                      },
                      "links": {
                        "html": "https://unsplash.com/photos/live-search",
                        "download_location": "https://api.unsplash.com/photos/live-search/download"
                      }
                    }
                  ]
                }
                """
                return (200, Data(body.utf8))
            }

            if request.url?.path == "/photos/live-search/download" {
                return (200, Data("{}".utf8))
            }

            Issue.record("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
            return (404, Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockUnsplashURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let service = ArticleFallbackImageService(
            modelContainer: container,
            keychainService: keychainService,
            urlSession: session
        )
        let repo = LocalArticleRepository(modelContainer: container)

        let url = await service.ensureFallbackImage(articleID: article.id)
        let stored = try #require(await repo.get(id: article.id))

        #expect(url == "https://images.unsplash.com/photo-live-search")
        #expect(stored.fallbackImageProvider == "unsplash_search")
        #expect(stored.fallbackImagePhotographerName == "Taylor Lens")
        #expect(stored.fallbackImagePhotographerProfileUrl?.contains("utm_source=nebularnews_ios") == true)
        #expect(stored.fallbackImagePhotoPageUrl?.contains("utm_medium=referral") == true)
    }

    @Test("Deterministic fallback remains when no Unsplash key is available")
    func deterministicFallbackWithoutKey() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Nature Boost")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Wildlife corridor expansion",
            content: String(repeating: "Wildlife conservation nature habitat corridor article. ", count: 60)
        )

        let service = ArticleFallbackImageService(modelContainer: container)
        let repo = LocalArticleRepository(modelContainer: container)

        let url = await service.ensureFallbackImage(articleID: article.id)
        let stored = try #require(await repo.get(id: article.id))

        #expect(url?.contains("images.unsplash.com/photo-") == true)
        #expect(stored.fallbackImageProvider != "unsplash_search")
        #expect(stored.fallbackImagePhotographerName == nil)
    }

    @Test("Existing preset fallback images are requeued after image revision bumps")
    func existingFallbackImagesRequeueForUpgrade() async throws {
        let container = try makeContainer()
        let context = makeContext(container)
        let feed = try insertFeed(in: context, title: "Example Feed")
        let article = try insertArticle(
            in: context,
            feed: feed,
            title: "Needs image refresh",
            content: String(repeating: "A software engineering article. ", count: 40)
        )
        article.fallbackImageUrl = "https://images.unsplash.com/photo-old"
        article.fallbackImageProvider = "deterministic"
        article.imagePreparedRevision = currentImagePreparationRevision - 1
        try context.save()

        let repo = LocalArticleRepository(modelContainer: container)
        try await repo.enqueueMissingProcessingJobs(for: article.id)
        let job = await repo.processingJob(articleID: article.id, stage: .resolveImage)

        #expect(job?.status == .queued)
        #expect(job?.inputRevision == currentImagePreparationRevision)
    }
}

private final class MockUnsplashURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URLRequest) throws -> (Int, Data) = { _ in
        (404, Data())
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (statusCode, data) = try Self.handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
