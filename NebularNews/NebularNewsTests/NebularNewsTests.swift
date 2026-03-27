//
//  NebularNewsTests.swift
//  NebularNewsTests
//
//  Created by Taylor Finklea on 3/5/26.
//

import Foundation
import Testing
import NebularNewsKit
@testable import NebularNews

private final class BundleProbe {}

struct NebularNewsTests {
    @MainActor
    @Test func appConfigurationFallsBackToGenericDefaults() async throws {
        let bundle = Bundle(for: BundleProbe.self)
        let expectedBundleIdentifier = bundle.bundleIdentifier ?? "com.example.nebularnews.ios"
        let configuration = AppConfiguration(bundle: bundle)

        #expect(configuration.bundleIdentifier == expectedBundleIdentifier)
        #expect(configuration.keychainService == expectedBundleIdentifier)
        #expect(configuration.backgroundRefreshTaskIdentifier == "\(expectedBundleIdentifier).feedRefresh")
        #expect(configuration.mobileOAuthClientId == "nebular-news-ios")
        #expect(configuration.mobileOAuthClientName == "Nebular News iOS")
        #expect(configuration.mobileOAuthRedirectURI.absoluteString == "nebularnews://oauth/callback")
        #expect(configuration.mobileDefaultServerURL.absoluteString == "https://app.nebularnews.com")
    }

    @Test func articleScoreHelpersReflectReadyAndLearningStates() async throws {
        let readyArticle = Article(canonicalUrl: "https://example.com/a", title: "Ready")
        readyArticle.score = 4
        readyArticle.scoreStatus = LocalScoreStatus.ready.rawValue
        readyArticle.scoreLabel = "Algorithmic (84% confidence)"

        #expect(readyArticle.hasReadyScore == true)
        #expect(readyArticle.isLearningScore == false)
        #expect(readyArticle.displayScoreLabel == "Algorithmic (84% confidence)")

        let learningArticle = Article(canonicalUrl: "https://example.com/b", title: "Learning")
        learningArticle.scoreStatus = LocalScoreStatus.insufficientSignal.rawValue

        #expect(learningArticle.hasReadyScore == false)
        #expect(learningArticle.isLearningScore == true)
        #expect(learningArticle.displayScoreLabel == "Learning your preferences")
    }

    @Test func articleReadingListHelpersTrackSavedState() async throws {
        let article = Article(canonicalUrl: "https://example.com/reading-list", title: "Saved")
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(article.isInReadingList == false)
        #expect(article.readingListAddedAt == nil)

        article.addToReadingList(at: savedAt)

        #expect(article.isInReadingList)
        #expect(article.readingListAddedAt == savedAt)

        article.toggleReadingList()

        #expect(article.isInReadingList == false)
        #expect(article.readingListAddedAt == nil)
    }

}
