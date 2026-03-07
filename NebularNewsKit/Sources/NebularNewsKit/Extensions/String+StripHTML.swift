import Foundation

extension String {
    /// Strip HTML tags and decode common entities, returning plain text.
    ///
    /// Used by the AI enrichment pipeline to convert `contentHtml` into
    /// clean text for LLM prompts. Also usable as a fallback renderer
    /// in views when `NSAttributedString` HTML parsing fails.
    public var strippedHTML: String {
        self
            // Remove HTML tags
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            // Decode common HTML entities
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            // Collapse runs of whitespace into a single space
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncate to a maximum character count, appending "…" if truncated.
    ///
    /// Used to cap article content sent to LLM prompts to stay within
    /// token budgets (roughly 4 chars ≈ 1 token for English text).
    public func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[startIndex..<end]) + "…"
    }
}
