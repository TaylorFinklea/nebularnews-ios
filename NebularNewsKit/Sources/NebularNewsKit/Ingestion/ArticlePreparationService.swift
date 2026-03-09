import Foundation
import SwiftData

public actor ArticlePreparationService {
    private let articleRepo: LocalArticleRepository
    private let settingsRepo: LocalSettingsRepository
    private let contentFetcher: ArticleContentFetcher
    private let ogImageFetcher: OGImageFetcher
    private let fallbackImageService: ArticleFallbackImageService
    private let personalization: LocalStandalonePersonalizationService
    private let enricher: AIEnrichmentService

    public init(
        modelContainer: ModelContainer,
        keychainService: String = "com.nebularnews.ios",
        generationCoordinator: (any AIGenerationCoordinating)? = nil
    ) {
        self.articleRepo = LocalArticleRepository(modelContainer: modelContainer)
        self.settingsRepo = LocalSettingsRepository(modelContainer: modelContainer)
        self.contentFetcher = ArticleContentFetcher(modelContainer: modelContainer)
        self.ogImageFetcher = OGImageFetcher(modelContainer: modelContainer)
        self.fallbackImageService = ArticleFallbackImageService(modelContainer: modelContainer)
        self.personalization = LocalStandalonePersonalizationService(
            modelContainer: modelContainer,
            keychainService: keychainService,
            generationCoordinator: generationCoordinator
        )
        self.enricher = AIEnrichmentService(
            modelContainer: modelContainer,
            keychainService: keychainService,
            generationCoordinator: generationCoordinator
        )
    }

    public func pendingPresentationCount() async -> Int {
        var filter = ArticleFilter()
        filter.presentationFilter = .pendingOnly
        return await articleRepo.count(filter: filter)
    }

    @discardableResult
    public func processPendingArticles(batchSize: Int = 10) async -> Int {
        var filter = ArticleFilter()
        filter.presentationFilter = .pendingOnly
        let candidates = await articleRepo.list(filter: filter, sort: .newest, limit: batchSize, offset: 0)
        let articleIDs = candidates.map(\.id)

        guard !articleIDs.isEmpty else {
            return 0
        }

        let dependencies = PreparationDependencies(
            articleRepo: articleRepo,
            settingsRepo: settingsRepo,
            contentFetcher: contentFetcher,
            ogImageFetcher: ogImageFetcher,
            fallbackImageService: fallbackImageService,
            personalization: personalization,
            enricher: enricher
        )

        return await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            var iterator = articleIDs.makeIterator()
            let initialConcurrency = min(2, articleIDs.count)

            for _ in 0..<initialConcurrency {
                guard let articleID = iterator.next() else { break }
                group.addTask {
                    await preparePendingArticle(articleID: articleID, dependencies: dependencies)
                }
            }

            var completed = 0

            while let succeeded = await group.next() {
                if succeeded {
                    completed += 1
                }

                if let nextArticleID = iterator.next() {
                    group.addTask {
                        await preparePendingArticle(articleID: nextArticleID, dependencies: dependencies)
                    }
                }
            }

            return completed
        }
    }
}

private struct PreparationDependencies: Sendable {
    let articleRepo: LocalArticleRepository
    let settingsRepo: LocalSettingsRepository
    let contentFetcher: ArticleContentFetcher
    let ogImageFetcher: OGImageFetcher
    let fallbackImageService: ArticleFallbackImageService
    let personalization: LocalStandalonePersonalizationService
    let enricher: AIEnrichmentService
}

private func preparePendingArticle(
    articleID: String,
    dependencies: PreparationDependencies
) async -> Bool {
    guard await dependencies.articleRepo.get(id: articleID) != nil else {
        return false
    }

    await prepareContentStage(articleID: articleID, dependencies: dependencies)
    await prepareImageStage(articleID: articleID, dependencies: dependencies)
    try? await dependencies.personalization.retagAndScoreArticle(articleID: articleID)
    await prepareEnrichmentStage(articleID: articleID, dependencies: dependencies)
    return true
}

private func prepareContentStage(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else {
        return
    }

    guard article.contentPreparationStatusValue == .pending else {
        return
    }

    if article.needsContentFetch() {
        let result = await dependencies.contentFetcher.fetchMissingContent(articleId: articleID)
        try? await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: mapContentPreparationStatus(result.status),
            image: nil,
            enrichment: nil
        )
        return
    }

    let status: ArticlePreparationStageStatus = article.bestAvailableContentLength >= 1_200
        ? .skipped
        : .blocked

    try? await dependencies.articleRepo.setPreparationState(
        id: articleID,
        content: status,
        image: nil,
        enrichment: nil
    )
}

private func prepareImageStage(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else {
        return
    }

    guard article.imagePreparationStatusValue == .pending else {
        return
    }

    if article.resolvedImageUrl != nil {
        try? await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: nil,
            image: .succeeded,
            enrichment: nil
        )
        return
    }

    if let canonicalURL = article.canonicalUrl,
       await dependencies.ogImageFetcher.fetchOGImage(articleId: articleID, canonicalUrl: canonicalURL) != nil {
        try? await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: nil,
            image: .succeeded,
            enrichment: nil
        )
        return
    }

    if await dependencies.fallbackImageService.ensureFallbackImage(articleID: articleID) != nil {
        try? await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: nil,
            image: .succeeded,
            enrichment: nil
        )
        return
    }

    try? await dependencies.articleRepo.setPreparationState(
        id: articleID,
        content: nil,
        image: .failed,
        enrichment: nil
    )
}

private func prepareEnrichmentStage(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else {
        return
    }

    guard article.enrichmentPreparationStatusValue == .pending else {
        return
    }

    guard let snapshot = await dependencies.articleRepo.enrichmentSnapshot(id: articleID) else {
        try? await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: nil,
            image: nil,
            enrichment: .blocked
        )
        return
    }

    let settings = await dependencies.settingsRepo.getOrCreate()
    let result = await dependencies.enricher.enrichArticle(
        snapshot: snapshot,
        summaryStyle: settings.summaryStyle,
        target: .automatic
    )

    let status: ArticlePreparationStageStatus
    switch result.status {
    case .generated:
        status = .succeeded
    case .skipped:
        status = .skipped
    case .failed:
        status = .failed
    }

    try? await dependencies.articleRepo.setPreparationState(
        id: articleID,
        content: nil,
        image: nil,
        enrichment: status
    )
}

private func mapContentPreparationStatus(
    _ status: ArticleContentFetchStatus
) -> ArticlePreparationStageStatus {
    switch status {
    case .fetched:
        return .succeeded
    case .skipped:
        return .skipped
    case .blocked:
        return .blocked
    case .failed:
        return .failed
    }
}
