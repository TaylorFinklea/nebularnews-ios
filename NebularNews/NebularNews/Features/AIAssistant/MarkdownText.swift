import SwiftUI

/// Lightweight block-level markdown renderer for assistant messages.
///
/// SwiftUI's `Text(LocalizedStringKey(...))` already renders inline
/// markdown (`**bold**`, `*italic*`, `[link](url)`, `` `code` ``), but
/// nothing for block-level syntax — `### heading`, `---`, `- list`,
/// `1. numbered`. The assistant frequently emits those when summarizing
/// briefs, and shipping them as raw `### Heading` text looks broken.
///
/// This walks the input line-by-line, classifies each line into one of
/// a small set of block kinds, and renders each as the right SwiftUI
/// view. Inline emphasis still goes through `LocalizedStringKey` so
/// `**bold**` etc. render correctly within paragraphs and list items.
///
/// Not a full CommonMark renderer — no tables, no blockquotes, no
/// fenced code blocks. Add those when the assistant actually emits
/// them; for now the goal is making `### AI & Tech` look like a
/// heading instead of three hashtags.
struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    /// One classified block of markdown — what kind of view it should
    /// render as. `text` carries the inline content (markdown still
    /// applies via LocalizedStringKey at render time).
    private enum Block {
        case heading(level: Int, text: String)
        case divider
        case bullet(text: String)
        case ordered(number: Int, text: String)
        case paragraph(String)
        case blank
    }

    /// Split the input into block-level pieces. Single newlines stay as
    /// implicit paragraph breaks because the assistant doesn't always
    /// emit double newlines around headings/lists.
    private var blocks: [Block] {
        var result: [Block] = []
        let lines = content.components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                result.append(.blank)
                continue
            }
            // ### Heading — count leading hashes (capped at 3 levels).
            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                let level = min(hashes.count, 3)
                let body = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty {
                    result.append(.heading(level: level, text: body))
                    continue
                }
            }
            // --- horizontal rule. Three or more hyphens, optional spaces.
            if line.range(of: #"^[-*_]{3,}$"#, options: .regularExpression) != nil {
                result.append(.divider)
                continue
            }
            // - bullet list (or *)
            if let match = line.range(of: #"^[-*]\s+"#, options: .regularExpression) {
                let body = String(line[match.upperBound...])
                result.append(.bullet(text: body))
                continue
            }
            // 1. numbered list
            if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let head = String(line[..<match.upperBound])
                let body = String(line[match.upperBound...])
                let numberStr = head.trimmingCharacters(in: .whitespaces).dropLast() // drop "."
                let number = Int(numberStr) ?? 0
                result.append(.ordered(number: number, text: body))
                continue
            }
            result.append(.paragraph(line))
        }
        return result
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(LocalizedStringKey(text))
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .padding(.top, 2)
        case .divider:
            Divider()
                .padding(.vertical, 2)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(LocalizedStringKey(text))
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        case .ordered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                Text(LocalizedStringKey(text))
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        case .paragraph(let text):
            Text(LocalizedStringKey(text))
                .font(.system(.body, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
        case .blank:
            // Collapse multiple blanks into a single small spacer.
            Color.clear.frame(height: 2)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}
