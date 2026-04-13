import Foundation

/// A segment of an assistant message — either text or an article card reference.
enum AssistantContentSegment: Identifiable {
    case text(String)
    case articleCard(id: String, title: String)

    var id: String {
        switch self {
        case .text(let t): return "text-\(t.prefix(20).hashValue)"
        case .articleCard(let id, _): return "card-\(id)"
        }
    }
}

/// Parses AI responses containing `[[article:ID:Title]]` references into segments.
enum AssistantMessageParser {

    /// Pattern: `[[article:ARTICLE_ID:Article Title]]`
    private static let articleRegex = try! NSRegularExpression(pattern: #"\[\[article:([^:]+):([^\]]+)\]\]"#)

    static func parse(_ content: String) -> [AssistantContentSegment] {
        var segments: [AssistantContentSegment] = []
        let nsContent = content as NSString
        let matches = articleRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var lastEnd = 0
        for match in matches {
            // Text before this match
            if match.range.location > lastEnd {
                let before = nsContent.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !before.isEmpty { segments.append(.text(before)) }
            }

            let articleId = nsContent.substring(with: match.range(at: 1))
            let articleTitle = nsContent.substring(with: match.range(at: 2))
            segments.append(.articleCard(id: articleId, title: articleTitle))

            lastEnd = match.range.location + match.range.length
        }

        // Remaining text after last match
        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd)
            if !remaining.isEmpty { segments.append(.text(remaining)) }
        }

        return segments.isEmpty ? [.text(content)] : segments
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
