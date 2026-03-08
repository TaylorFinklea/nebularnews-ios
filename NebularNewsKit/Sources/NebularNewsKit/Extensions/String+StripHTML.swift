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
            // Decode numeric HTML entities (&#8211; → –, &#160; → non-breaking space, etc.)
            .decodingNumericHTMLEntities
            // Collapse runs of whitespace into a single space
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode numeric HTML entities like `&#8211;` and `&#x2014;` into their
    /// corresponding Unicode characters.
    private var decodingNumericHTMLEntities: String {
        var result = self

        // Decimal: &#NNN;
        let decimalPattern = try? NSRegularExpression(pattern: "&#(\\d+);")
        if let matches = decimalPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[codeRange]),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        // Hexadecimal: &#xHHH;
        let hexPattern = try? NSRegularExpression(pattern: "&#x([0-9A-Fa-f]+);")
        if let matches = hexPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[codeRange], radix: 16),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        return result
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
