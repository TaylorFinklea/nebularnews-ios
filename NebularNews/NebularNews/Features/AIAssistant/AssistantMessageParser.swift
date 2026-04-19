import Foundation

/// A segment of an assistant message — text, an article card reference, or
/// a tool invocation result (M11 tool-calling).
enum AssistantContentSegment: Identifiable {
    case text(String)
    case articleCard(id: String, title: String)
    case toolResult(name: String, summary: String, succeeded: Bool, undo: UndoPayload?)

    /// Pair of (inverse-tool name, base64-encoded JSON args). When present,
    /// the chip renders an Undo button that POSTs to /chat/undo-tool.
    struct UndoPayload: Equatable, Hashable {
        let tool: String
        let argsB64: String
    }

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.prefix(20).hashValue)"
        case .articleCard(let id, _): return "card-\(id)"
        case .toolResult(let name, let summary, _, _): return "tool-\(name)-\(summary.hashValue)"
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
            // Tool markers can have 4 or 6 colon-separated parts:
            //   tool:name:summary:succeeded
            //   tool:name:summary:succeeded:undoTool:base64Args
            let parts = inner.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)

            if parts.count >= 3, parts[0] == "article" {
                // Article cards use maxSplits=3 semantics; rejoin in case title has colons.
                let title = parts.count > 3 ? parts[2...].joined(separator: ":") : parts[2]
                segments.append(.articleCard(id: parts[1], title: title))
            } else if parts.count >= 4, parts[0] == "tool" {
                let succeeded = parts[3] == "1"
                var undo: AssistantContentSegment.UndoPayload? = nil
                if parts.count >= 6, !parts[4].isEmpty {
                    undo = .init(tool: parts[4], argsB64: parts[5])
                }
                segments.append(.toolResult(name: parts[1], summary: parts[2], succeeded: succeeded, undo: undo))
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
    /// Optional undo payload encodes as `:undoTool:base64Args` appended.
    static func toolMarker(
        name: String,
        summary: String,
        succeeded: Bool,
        undoTool: String? = nil,
        undoArgsB64: String? = nil
    ) -> String {
        let safeName = name.replacingOccurrences(of: ":", with: "-")
        let safeSummary = summary.replacingOccurrences(of: ":", with: "-")
        let succ = succeeded ? "1" : "0"
        if let undoTool, !undoTool.isEmpty, let undoArgsB64, !undoArgsB64.isEmpty {
            return "\n[[tool:\(safeName):\(safeSummary):\(succ):\(undoTool):\(undoArgsB64)]]\n"
        }
        return "\n[[tool:\(safeName):\(safeSummary):\(succ)]]\n"
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
