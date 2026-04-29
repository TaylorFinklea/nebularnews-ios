import Foundation
import Observation

/// Per-tool confirmation policy for destructive AI assistant actions.
/// Backed by UserDefaults so the setting persists across launches without
/// iCloud sync (intentional — see spec decision notes).
@MainActor
@Observable
final class AIGuardrailsPolicy {
    enum Mode: String, CaseIterable, Codable, Sendable {
        case confirm
        case undoOnly
    }

    /// All destructive tools we can govern. Names match server tool names.
    static let governedTools: [String] = [
        "unsubscribe_from_feed",
        "mark_articles_read",       // only enforced when count > 5
        "pause_feed",               // only enforced when paused == true
        "set_feed_max_per_day",
        "set_feed_min_score",
    ]

    private let defaults: UserDefaults
    private static let prefix = "aiGuardrails.policy."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mode(for tool: String) -> Mode {
        guard let raw = defaults.string(forKey: Self.prefix + tool),
              let mode = Mode(rawValue: raw) else {
            return .confirm  // default: always confirm
        }
        return mode
    }

    func setMode(_ mode: Mode, for tool: String) {
        defaults.set(mode.rawValue, forKey: Self.prefix + tool)
    }

    /// Snapshot for the chat request body. Sends current policy for each governed tool.
    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for t in Self.governedTools {
            out[t] = mode(for: t).rawValue
        }
        return out
    }
}
