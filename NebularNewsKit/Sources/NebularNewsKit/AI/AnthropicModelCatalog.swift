import Foundation

public struct AnthropicModelOption: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum AnthropicModelCatalog {
    public static let defaultModelID = "claude-haiku-4-5-20251001"

    public static let fallbackOptions: [AnthropicModelOption] = [
        AnthropicModelOption(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5"),
        AnthropicModelOption(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
        AnthropicModelOption(id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5"),
        AnthropicModelOption(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4"),
        AnthropicModelOption(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
        AnthropicModelOption(id: "claude-opus-4-5-20251101", displayName: "Claude Opus 4.5"),
        AnthropicModelOption(id: "claude-opus-4-1-20250805", displayName: "Claude Opus 4.1"),
        AnthropicModelOption(id: "claude-opus-4-20250514", displayName: "Claude Opus 4")
    ]

    public static func resolve(preferred: String?) -> String {
        guard let preferred,
              fallbackOptions.contains(where: { $0.id == preferred }) || preferred.lowercased().contains("claude")
        else {
            return defaultModelID
        }
        return preferred
    }

    public static func label(for modelID: String) -> String {
        fallbackOptions.first(where: { $0.id == modelID })?.displayName ?? modelID
    }

    public static func mergedOptions(
        fetched: [AnthropicModelDescriptor],
        including selectedModelID: String? = nil
    ) -> [AnthropicModelOption] {
        let fetchedOptions = fetched
            .filter { $0.id.lowercased().contains("claude") }
            .map { AnthropicModelOption(id: $0.id, displayName: $0.displayName ?? prettyName(for: $0.id)) }

        var byID = Dictionary(uniqueKeysWithValues: fallbackOptions.map { ($0.id, $0) })
        for option in fetchedOptions {
            byID[option.id] = option
        }

        if let selectedModelID, byID[selectedModelID] == nil {
            byID[selectedModelID] = AnthropicModelOption(
                id: selectedModelID,
                displayName: prettyName(for: selectedModelID)
            )
        }

        let priority = Dictionary(
            uniqueKeysWithValues: fallbackOptions.enumerated().map { ($0.element.id, $0.offset) }
        )

        return byID.values.sorted { lhs, rhs in
            let lhsPriority = priority[lhs.id] ?? Int.max
            let rhsPriority = priority[rhs.id] ?? Int.max
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func prettyName(for modelID: String) -> String {
        let normalized = modelID
            .replacingOccurrences(of: "claude-", with: "Claude ")
            .replacingOccurrences(of: "-", with: " ")
        return normalized
            .split(separator: " ")
            .map { part in
                if part.allSatisfy(\.isNumber) {
                    return String(part)
                }
                return part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
