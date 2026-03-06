import Foundation
import Observation
import NebularNewsKit

/// Root application state. Tracks onboarding completion and global UI state.
@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    let keychain = KeychainManager()

    var hasAnthropicKey: Bool {
        keychain.has(key: KeychainManager.Key.anthropicApiKey)
    }

    var hasOpenAIKey: Bool {
        keychain.has(key: KeychainManager.Key.openaiApiKey)
    }

    var hasAnyAIKey: Bool {
        hasAnthropicKey || hasOpenAIKey
    }
}
