import Foundation
import NebularNewsKit
import os

/// Where AI inference for this user runs. Resolved from the server's
/// usage summary (paid subscription tier) plus a local check of the
/// Keychain (BYOK keys) and FoundationModels availability. The fallback
/// when nothing else applies is `.onDevice` if the device supports it,
/// else `.unavailable`.
enum AITier: Equatable, Sendable {
    case onDevice
    case byok(provider: String)
    case subscription(planName: String)
    case unavailable

    var displayLabel: String {
        switch self {
        case .onDevice: return "On-device"
        case .byok(let provider): return "BYOK · \(provider.capitalized)"
        case .subscription(let plan): return plan.capitalized
        case .unavailable: return "AI unavailable"
        }
    }

    var caption: String {
        switch self {
        case .onDevice:
            return "Running locally on your iPhone with Apple Intelligence."
        case .byok(let provider):
            return "Using your \(provider.capitalized) API key."
        case .subscription:
            return "Included in your NebularNews subscription."
        case .unavailable:
            return "Add an API key or subscribe to enable AI features."
        }
    }

    /// Used by the streaming bubble caption while a response generates.
    /// Nil for paid/BYOK paths so we don't visually clutter the common case.
    var streamingBadge: String? {
        switch self {
        case .onDevice: return "On-device · Apple Intelligence"
        default: return nil
        }
    }
}

/// Single source of truth for which AI tier the app is currently
/// operating under. Read by `StreamingChatService` once per send to
/// decide whether to route to the server SSE path or the on-device
/// FoundationModels path. Process-wide singleton — owned by AppState
/// for its lifecycle, but accessible from non-environment surfaces
/// (e.g. service classes) via `AIRouting.shared`.
@MainActor
@Observable
final class AIRouting {
    static let shared = AIRouting()

    private(set) var current: AITier = .onDevice
    private let logger = Logger(subsystem: "com.nebularnews", category: "AIRouting")

    /// Refresh by fetching the latest usage summary (server-determined
    /// tier) and re-checking local key + on-device runtime state. Safe
    /// to call repeatedly; no network call when the user has no session.
    func refresh() async {
        // BYOK takes precedence over on-device per
        // feedback_no_background_device_ai.md — when the user has a key,
        // requests are server-proxied so they get the full tool suite.
        let keychain = KeychainManager(service: "com.nebularnews.ios")
        let hasAnthropic = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) != nil
        let hasOpenAI = keychain.get(forKey: KeychainManager.Key.openaiApiKey) != nil

        // Fetch tier from server (best-effort — no session means no
        // subscription, so we fall through to BYOK / on-device).
        var serverTier: String? = nil
        if APIClient.shared.hasSession {
            do {
                let usage: UsageSummaryResponse = try await APIClient.shared.request(path: "api/usage/summary")
                serverTier = usage.tier
            } catch {
                logger.debug("Usage summary fetch failed; assuming no subscription: \(error.localizedDescription)")
            }
        }

        if let tier = serverTier, !tier.isEmpty {
            current = .subscription(planName: tier)
        } else if hasAnthropic {
            current = .byok(provider: "anthropic")
        } else if hasOpenAI {
            current = .byok(provider: "openai")
        } else if FoundationModelsEngine.runtimeAvailable {
            current = .onDevice
        } else {
            current = .unavailable
        }
        logger.info("AI tier resolved: \(self.current.displayLabel)")
    }
}
