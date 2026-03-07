//
//  NebularNewsTests.swift
//  NebularNewsTests
//
//  Created by Taylor Finklea on 3/5/26.
//

import Foundation
import Testing
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
}
