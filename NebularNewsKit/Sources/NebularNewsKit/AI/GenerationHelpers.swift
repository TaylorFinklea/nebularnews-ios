import Foundation

enum GenerationParsingError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The model returned an invalid response."
        }
    }
}

func extractJSONObjectString(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
        return trimmed
    }

    if let fenceRange = trimmed.range(of: "```json") ?? trimmed.range(of: "```") {
        let afterFence = trimmed[fenceRange.upperBound...]
        if let endRange = afterFence.range(of: "```") {
            return String(afterFence[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    guard let start = trimmed.firstIndex(of: "{"),
          let end = trimmed.lastIndex(of: "}")
    else {
        return nil
    }

    return String(trimmed[start...end])
}

func parseJSONObject(from text: String) throws -> [String: Any] {
    guard let jsonString = extractJSONObjectString(from: text),
          let data = jsonString.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw GenerationParsingError.invalidResponse
    }
    return object
}

func normalizedSuggestionName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

func parseSummaryOutput(
    from text: String,
    provider: AIGenerationProvider,
    modelIdentifier: String?
) throws -> SummaryGenerationOutput {
    let object = try parseJSONObject(from: text)
    let summary = String(describing: object["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let keyPoints = (object["key_points"] as? [Any] ?? [])
        .map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !summary.isEmpty, !keyPoints.isEmpty else {
        throw GenerationParsingError.invalidResponse
    }

    return SummaryGenerationOutput(
        summary: summary,
        keyPoints: Array(keyPoints.prefix(4)),
        provider: provider,
        modelIdentifier: modelIdentifier
    )
}

func parseTagSuggestionCandidates(from text: String, maxSuggestions: Int) throws -> [SuggestedTagCandidate] {
    let object = try parseJSONObject(from: text)
    let rawSuggestions = (object["new_suggestions"] as? [Any] ?? object["suggestions"] as? [Any] ?? [])

    return rawSuggestions.compactMap { entry in
        if let string = entry as? String {
            let name = normalizedSuggestionName(string)
            guard !name.isEmpty else { return nil }
            return SuggestedTagCandidate(name: name, confidence: 0)
        }

        guard let row = entry as? [String: Any] else { return nil }
        let name = normalizedSuggestionName(String(describing: row["name"] ?? row["tag"] ?? ""))
        guard !name.isEmpty else { return nil }
        let confidence = max(0, min(1, row["confidence"] as? Double ?? row["score"] as? Double ?? 0))
        return SuggestedTagCandidate(name: name, confidence: confidence)
    }
    .prefix(maxSuggestions)
    .map { $0 }
}

func parseScoreAssistOutput(
    from text: String,
    provider: AIGenerationProvider,
    modelIdentifier: String?
) throws -> ScoreAssistOutput {
    let object = try parseJSONObject(from: text)
    let explanation = String(describing: object["explanation"] ?? object["reason"] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let adjustment = Int(object["adjustment"] as? Int ?? Int((object["adjustment"] as? Double ?? 0).rounded()))

    guard !explanation.isEmpty else {
        throw GenerationParsingError.invalidResponse
    }

    return ScoreAssistOutput(
        explanation: explanation,
        adjustment: max(-1, min(1, adjustment)),
        provider: provider,
        modelIdentifier: modelIdentifier
    )
}
