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
        #expect(configuration.cloudKitEnabled == false)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.mobileOAuthClientId == "nebular-news-ios")
        #expect(configuration.mobileOAuthClientName == "Nebular News iOS")
        #expect(configuration.mobileOAuthRedirectURI.absoluteString == "nebularnews://oauth/callback")
        #expect(configuration.mobileDefaultServerURL == nil)
    }

    @MainActor
    @Test func appStateCompletesStandaloneOnboardingAndPersistsObservableState() async throws {
        let bundle = Bundle(for: BundleProbe.self)
        let configuration = AppConfiguration(bundle: bundle)
        let suiteName = "NebularNewsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appState = AppState(configuration: configuration, defaults: defaults)

        #expect(appState.hasCompletedOnboarding == false)
        #expect(appState.mode == .standalone)

        appState.completeStandaloneOnboarding()

        #expect(appState.hasCompletedOnboarding == true)
        #expect(appState.mode == .standalone)
        #expect(defaults.bool(forKey: "hasCompletedOnboarding") == true)
        #expect(defaults.string(forKey: "appMode") == "standalone")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    @Test func appStatePersistsFirstBriefingWarmupState() async throws {
        let bundle = Bundle(for: BundleProbe.self)
        let configuration = AppConfiguration(bundle: bundle)
        let suiteName = "NebularNewsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appState = AppState(configuration: configuration, defaults: defaults)
        appState.beginStandaloneFirstBriefing(feedIDs: ["feed-1", "feed-2"])

        #expect(appState.isPreparingFirstBriefing)
        #expect(appState.firstBriefingFeedIDs == ["feed-1", "feed-2"])
        #expect(defaults.bool(forKey: "isPreparingFirstBriefing"))
        #expect(defaults.stringArray(forKey: "firstBriefingFeedIDs") == ["feed-1", "feed-2"])

        appState.finishStandaloneFirstBriefingWarmup()

        #expect(appState.isPreparingFirstBriefing == false)
        #expect(appState.firstBriefingFeedIDs.isEmpty)
        #expect(defaults.bool(forKey: "isPreparingFirstBriefing") == false)
        #expect(defaults.stringArray(forKey: "firstBriefingFeedIDs") == [])

        defaults.removePersistentDomain(forName: suiteName)
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

    @Test func readingListContentFiltersAndSortsBySaveDateThenPublishDate() async throws {
        let oldestSaved = Article(canonicalUrl: "https://example.com/1", title: "Birding Dispatch")
        oldestSaved.feed = Feed(feedUrl: "https://example.com/feed", title: "Birding Weekly")
        oldestSaved.readingListAddedAt = Date(timeIntervalSince1970: 100)
        oldestSaved.publishedAt = Date(timeIntervalSince1970: 1_000)

        let newestSavedUnread = Article(canonicalUrl: "https://example.com/2", title: "City Budget Vote")
        newestSavedUnread.feed = Feed(feedUrl: "https://example.com/local", title: "Kansas City Today")
        newestSavedUnread.readingListAddedAt = Date(timeIntervalSince1970: 300)
        newestSavedUnread.publishedAt = Date(timeIntervalSince1970: 900)

        let newestSavedRead = Article(canonicalUrl: "https://example.com/3", title: "Transit Expansion")
        newestSavedRead.feed = Feed(feedUrl: "https://example.com/local", title: "Kansas City Today")
        newestSavedRead.readingListAddedAt = Date(timeIntervalSince1970: 300)
        newestSavedRead.publishedAt = Date(timeIntervalSince1970: 950)
        newestSavedRead.markRead(at: Date(timeIntervalSince1970: 400))

        let ordered = ReadingListContent.filteredArticles(
            from: [oldestSaved, newestSavedUnread, newestSavedRead],
            searchText: "",
            filterMode: .all
        )

        #expect(ordered.compactMap(\.title) == ["Transit Expansion", "City Budget Vote", "Birding Dispatch"])

        let unreadOnly = ReadingListContent.filteredArticles(
            from: [oldestSaved, newestSavedUnread, newestSavedRead],
            searchText: "",
            filterMode: .unread
        )
        #expect(unreadOnly.compactMap(\.title) == ["City Budget Vote", "Birding Dispatch"])

        let searchResults = ReadingListContent.filteredArticles(
            from: [oldestSaved, newestSavedUnread, newestSavedRead],
            searchText: "Kansas",
            filterMode: .all
        )
        #expect(searchResults.compactMap(\.title) == ["Transit Expansion", "City Budget Vote"])
    }
}
