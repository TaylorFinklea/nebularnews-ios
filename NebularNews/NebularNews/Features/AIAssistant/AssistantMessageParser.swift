import Foundation

/// A segment of an assistant message — text, an article card reference, or
/// a tool invocation result (M11 tool-calling).
enum AssistantContentSegment: Identifiable {
    case text(String)
    case articleCard(id: String, title: String)
    case toolResult(name: String, summary: String, succeeded: Bool)

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.prefix(20).hashValue)"
        case .articleCard(let id, _): return "card-\(id)"
        case .toolResult(let name, let summary, _): return "tool-\(name)-\(summary.hashValue)"
        }
    }
}

/// Parses AI responses containing `[[article:ID:Title]]` and
/// `[[tool:NAME:SUMMARY:1|0]]` inline markers into segments.
enum AssistantMessageParser {

    /// Matches either:
    ///   [[article:ARTICLE_ID:Article Title]]
    ///   [[tool:TOOL_NAME:Summary text:1]]   (succeeded=1/0 at the end)
    private static let markerRegex = try! NSRegularExpression(pattern: #"\[\[(?:article|tool):[^\]]+\]\]"#)

    static func parse(_ content: String) -> [AssistantContentSegment] {
        var segments: [AssistantContentSegment] = []
        let nsContent = content as NSString
        let matches = markerRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var lastEnd = 0
        for match in matches {
            if match.range.location > lastEnd {
                let before = nsContent.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !before.isEmpty { segments.append(.text(before)) }
            }

            let markerContent = nsContent.substring(with: match.range)
            // Strip leading [[ and trailing ]]
            let inner = String(markerContent.dropFirst(2).dropLast(2))
            let parts = inner.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)

            if parts.count >= 3, parts[0] == "article" {
                segments.append(.articleCard(id: parts[1], title: parts[2]))
            } else if parts.count == 4, parts[0] == "tool" {
                let succeeded = parts[3] == "1"
                segments.append(.toolResult(name: parts[1], summary: parts[2], succeeded: succeeded))
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd)
            if !remaining.isEmpty { segments.append(.text(remaining)) }
        }

        return segments.isEmpty ? [.text(content)] : segments
    }

    /// Build the inline marker a coordinator injects when a tool result arrives.
    static func toolMarker(name: String, summary: String, succeeded: Bool) -> String {
        // Strip colons from name/summary so our split logic stays sane.
        let safeName = name.replacingOccurrences(of: ":", with: "-")
        let safeSummary = summary.replacingOccurrences(of: ":", with: "-")
        return "\n[[tool:\(safeName):\(safeSummary):\(succeeded ? "1" : "0")]]\n"
    }

    /// Extract follow-up suggestions (lines starting with >>).
    static func extractSuggestions(from content: String) -> (cleanContent: String, suggestions: [String]) {
        let lines = content.components(separatedBy: "\n")
        var textLines: [String] = []
        var suggestions: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">>") {
                let q = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !q.isEmpty { suggestions.append(q) }
            } else {
                textLines.append(line)
            }
        }

        // Trim trailing empty lines.
        while let last = textLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            textLines.removeLast()
        }

        return (textLines.joined(separator: "\n"), suggestions)
    }
}
