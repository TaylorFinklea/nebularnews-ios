import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nebularnews", category: "ArticlePreparation")

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
        self.fallbackImageService = ArticleFallbackImageService(
            modelContainer: modelContainer,
            keychainService: keychainService
        )
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
        await articleRepo.pendingVisibleArticleCount()
    }

    @discardableResult
    public func processPendingArticles(
        batchSize: Int = 10,
        allowLowPriority: Bool = true
    ) async -> Int {
        let claimedKeys = await articleRepo.claimProcessingJobs(
            limit: batchSize,
            allowLowPriority: allowLowPriority
        )

        guard !claimedKeys.isEmpty else {
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

        let completed = await withTaskGroup(of: Void.self, returning: Int.self) { group in
            var iterator = claimedKeys.makeIterator()
            let maxConcurrency = min(2, claimedKeys.count)

            for _ in 0..<maxConcurrency {
                guard let key = iterator.next() else { break }
                group.addTask {
                    await processJob(key: key, dependencies: dependencies)
                }
            }

            var count = 0
            while await group.next() != nil {
                count += 1
                if let key = iterator.next() {
                    group.addTask {
                        await processJob(key: key, dependencies: dependencies)
                    }
                }
            }

            return count
        }

        if completed > 0 {
            await articleRepo.rebuildTodaySnapshot()
            ArticleChangeBus.postFeedPageMightChange()
            ArticleChangeBus.postProcessingQueueChanged()
        }

        return completed
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

private func processJob(
    key: String,
    dependencies: PreparationDependencies
) async {
    guard let parsed = parseJobKey(key) else { return }

    switch parsed.stage {
    case .scoreAndTag:
        await processScoreJob(articleID: parsed.articleID, dependencies: dependencies)
    case .fetchContent:
        await processContentJob(articleID: parsed.articleID, dependencies: dependencies)
    case .generateSummary:
        await processSummaryJob(articleID: parsed.articleID, dependencies: dependencies)
    case .resolveImage:
        await processImageJob(articleID: parsed.articleID, dependencies: dependencies)
    }
}

private func processScoreJob(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else { return }
    let revision = max(article.contentRevision, currentPersonalizationVersion)

    do {
        try await dependencies.personalization.prepareVisibleScore(articleID: articleID)
        try await dependencies.articleRepo.completeProcessingJob(
            articleID: articleID,
            stage: .scoreAndTag,
            status: .done,
            inputRevision: revision,
            error: nil,
            suppressNotification: true
        )
        ArticleChangeBus.postArticleChanged(id: articleID)
    } catch {
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .scoreAndTag,
                status: .failed,
                inputRevision: revision,
                error: error.localizedDescription,
                suppressNotification: true
            )
        } catch {
            logger.error("Failed to save score job failure for \(articleID): \(error)")
        }
    }
}

private func processContentJob(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else { return }
    let revision = article.contentRevision

    guard article.needsContentFetch() else {
        let status: ArticlePreparationStageStatus = article.bestAvailableContentLength >= 1_200 ? .skipped : .blocked
        do {
            try await dependencies.articleRepo.setPreparationState(
                id: articleID,
                content: status,
                image: nil,
                enrichment: nil
            )
        } catch {
            logger.error("Failed to set content preparation state for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .fetchContent,
                status: status == .failed ? .failed : .skipped,
                inputRevision: revision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete content job (skip) for \(articleID): \(error)")
        }
        return
    }

    let result = await dependencies.contentFetcher.fetchMissingContent(articleId: articleID)
    do {
        try await dependencies.articleRepo.setPreparationState(
            id: articleID,
            content: mapContentPreparationStatus(result.status),
            image: nil,
            enrichment: nil
        )
    } catch {
        logger.error("Failed to set content preparation state for \(articleID): \(error)")
    }

    let jobStatus: ArticleProcessingJobStatus
    switch result.status {
    case .fetched:
        jobStatus = .done
        do {
            try await dependencies.articleRepo.enqueueMissingProcessingJobs(for: articleID)
        } catch {
            logger.error("Failed to enqueue missing jobs for \(articleID): \(error)")
        }
    case .skipped, .blocked:
        jobStatus = .skipped
    case .failed:
        jobStatus = .failed
    }

    let jobError: String? = switch result.status {
    case .failed:
        "Content extraction failed"
    case .blocked:
        "Content source blocked extraction"
    default:
        nil
    }

    do {
        try await dependencies.articleRepo.completeProcessingJob(
            articleID: articleID,
            stage: .fetchContent,
            status: jobStatus,
            inputRevision: revision,
            error: jobError
        )
    } catch {
        logger.error("Failed to complete content job for \(articleID): \(error)")
    }
}

private func processSummaryJob(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else { return }
    let revision = article.contentRevision

    guard let snapshot = await dependencies.articleRepo.enrichmentSnapshot(id: articleID) else {
        do {
            try await dependencies.articleRepo.markSummaryAttempt(
                id: articleID,
                status: .blocked,
                revision: revision
            )
        } catch {
            logger.error("Failed to mark summary blocked for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .generateSummary,
                status: .skipped,
                inputRevision: revision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete summary job (blocked) for \(articleID): \(error)")
        }
        return
    }

    let settings = await dependencies.settingsRepo.getOrCreate()
    let result = await dependencies.enricher.enrichArticle(
        snapshot: snapshot,
        summaryStyle: settings.summaryStyle,
        target: .automatic
    )

    switch result.status {
    case .generated:
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .generateSummary,
                status: .done,
                inputRevision: revision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete summary job (done) for \(articleID): \(error)")
        }
    case .skipped:
        do {
            try await dependencies.articleRepo.markSummaryAttempt(
                id: articleID,
                status: .skipped,
                revision: revision
            )
        } catch {
            logger.error("Failed to mark summary skipped for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .generateSummary,
                status: .skipped,
                inputRevision: revision,
                error: result.error
            )
        } catch {
            logger.error("Failed to complete summary job (skipped) for \(articleID): \(error)")
        }
    case .failed:
        do {
            try await dependencies.articleRepo.markSummaryAttempt(
                id: articleID,
                status: .failed,
                revision: revision
            )
        } catch {
            logger.error("Failed to mark summary failed for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .generateSummary,
                status: .failed,
                inputRevision: revision,
                error: result.error
            )
        } catch {
            logger.error("Failed to complete summary job (failed) for \(articleID): \(error)")
        }
    }
}

private func processImageJob(
    articleID: String,
    dependencies: PreparationDependencies
) async {
    guard let article = await dependencies.articleRepo.get(id: articleID) else { return }
    let existingFallback = article.fallbackImageUrl

    if article.imageUrl != nil || article.ogImageUrl != nil {
        do {
            try await dependencies.articleRepo.markImageAttempt(
                id: articleID,
                status: .succeeded,
                revision: currentImagePreparationRevision
            )
        } catch {
            logger.error("Failed to mark image succeeded for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .resolveImage,
                status: .done,
                inputRevision: currentImagePreparationRevision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete image job (existing) for \(articleID): \(error)")
        }
        return
    }

    if let canonicalURL = article.canonicalUrl,
       await dependencies.ogImageFetcher.fetchOGImage(articleId: articleID, canonicalUrl: canonicalURL) != nil {
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .resolveImage,
                status: .done,
                inputRevision: currentImagePreparationRevision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete image job (og) for \(articleID): \(error)")
        }
        return
    }

    if await dependencies.fallbackImageService.ensureFallbackImage(articleID: articleID) != nil {
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .resolveImage,
                status: .done,
                inputRevision: currentImagePreparationRevision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete image job (fallback) for \(articleID): \(error)")
        }
        return
    }

    if existingFallback != nil {
        do {
            try await dependencies.articleRepo.markImageAttempt(
                id: articleID,
                status: .succeeded,
                revision: currentImagePreparationRevision
            )
        } catch {
            logger.error("Failed to mark image succeeded (existing fallback) for \(articleID): \(error)")
        }
        do {
            try await dependencies.articleRepo.completeProcessingJob(
                articleID: articleID,
                stage: .resolveImage,
                status: .done,
                inputRevision: currentImagePreparationRevision,
                error: nil
            )
        } catch {
            logger.error("Failed to complete image job (existing fallback) for \(articleID): \(error)")
        }
        return
    }

    do {
        try await dependencies.articleRepo.markImageAttempt(
            id: articleID,
            status: .failed,
            revision: currentImagePreparationRevision
        )
    } catch {
        logger.error("Failed to mark image failed for \(articleID): \(error)")
    }
    do {
        try await dependencies.articleRepo.completeProcessingJob(
            articleID: articleID,
            stage: .resolveImage,
            status: .failed,
            inputRevision: currentImagePreparationRevision,
            error: "No image source available"
        )
    } catch {
        logger.error("Failed to complete image job (no source) for \(articleID): \(error)")
    }
}

private func parseJobKey(_ key: String) -> (articleID: String, stage: ArticleProcessingStage)? {
    let marker = "::"
    guard let range = key.range(of: marker, options: .backwards) else { return nil }
    let articleID = String(key[..<range.lowerBound])
    let stageRaw = String(key[range.upperBound...])
    guard let stage = ArticleProcessingStage(rawValue: stageRaw) else { return nil }
    return (articleID, stage)
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
