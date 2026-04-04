import SwiftUI
import NebularNewsKit

// MARK: - Content Blocks

private enum ContentBlock {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case blockquote(AttributedString)
    case codeBlock(String)
    case image(url: URL, alt: String?)
    case unorderedList(items: [AttributedString])
    case orderedList(items: [AttributedString])
    case divider
}

// MARK: - Block Parser

private struct HTMLBlockParser {

    // Tags that introduce block-level structure in the rendered output
    private static let blockTags = ["p", "h1", "h2", "h3", "h4", "h5", "h6",
                                    "ul", "ol", "blockquote", "pre", "hr",
                                    "figure", "img"]

    static func parse(_ html: String) -> [ContentBlock] {
        let cleaned = removeParsedNoiseTags(html)
        var blocks: [ContentBlock] = []

        // Match block-level elements in document order
        let pattern = #"(?is)(<h[1-6]\b[^>]*>.*?</h[1-6]>|<blockquote\b[^>]*>.*?</blockquote>|<pre\b[^>]*>.*?</pre>|<ul\b[^>]*>.*?</ul>|<ol\b[^>]*>.*?</ol>|<figure\b[^>]*>.*?</figure>|<p\b[^>]*>.*?</p>|<img\b[^>]*/?> |<hr\b[^>]*/?>)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            let fallback = html.strippedHTML
            return fallback.isEmpty ? [] : [.paragraph(AttributedString(fallback))]
        }

        let matches = re.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        for match in matches {
            guard let range = Range(match.range, in: cleaned) else { continue }
            if let block = parseBlock(String(cleaned[range])) {
                blocks.append(block)
            }
        }

        if blocks.isEmpty {
            let fallback = html.strippedHTML
            if !fallback.isEmpty {
                blocks.append(.paragraph(AttributedString(fallback)))
            }
        }
        return blocks
    }

    // MARK: Individual Block Parsing

    private static func parseBlock(_ blockHTML: String) -> ContentBlock? {
        let tag = leadingTagName(blockHTML)

        switch tag {
        case "p":
            let inner = extractInnerHTML(blockHTML, tag: "p")
            let attr = parseInlineHTML(inner)
            return attr.characters.isEmpty ? nil : .paragraph(attr)

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.last!)) ?? 2
            let inner = extractInnerHTML(blockHTML, tag: tag)
            return .heading(level: level, text: parseInlineHTML(inner))

        case "blockquote":
            let inner = extractInnerHTML(blockHTML, tag: "blockquote")
            let stripped = inner.strippedHTML
            return stripped.isEmpty ? nil : .blockquote(AttributedString(stripped))

        case "pre":
            let codePattern = #"(?is)<code[^>]*>(.*?)</code>"#
            let inner: String
            if let re = try? NSRegularExpression(pattern: codePattern),
               let m = re.firstMatch(in: blockHTML, range: NSRange(blockHTML.startIndex..., in: blockHTML)),
               let r = Range(m.range(at: 1), in: blockHTML) {
                inner = String(blockHTML[r]).strippedHTML
            } else {
                inner = extractInnerHTML(blockHTML, tag: "pre").strippedHTML
            }
            return inner.isEmpty ? nil : .codeBlock(inner)

        case "ul":
            let items = extractListItems(blockHTML)
            return items.isEmpty ? nil : .unorderedList(items: items)

        case "ol":
            let items = extractListItems(blockHTML)
            return items.isEmpty ? nil : .orderedList(items: items)

        case "figure":
            return extractFigureImage(blockHTML)

        case "img":
            return extractStandaloneImage(blockHTML)

        case "hr":
            return .divider

        default:
            return nil
        }
    }

    // MARK: List Items

    private static func extractListItems(_ html: String) -> [AttributedString] {
        let pattern = #"(?is)<li\b[^>]*>(.*?)</li>"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            let inner = String(html[r])
            let attr = parseInlineHTML(inner)
            return attr.characters.isEmpty ? nil : attr
        }
    }

    // MARK: Image Extraction

    private static func extractFigureImage(_ html: String) -> ContentBlock? {
        let imgPattern = #"(?is)<img\b[^>]*/?>"#
        guard let re = try? NSRegularExpression(pattern: imgPattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range, in: html)
        else { return nil }
        return extractStandaloneImage(String(html[r]))
    }

    private static func extractStandaloneImage(_ imgTag: String) -> ContentBlock? {
        guard let src = extractAttr("src", from: imgTag),
              !src.isEmpty,
              let url = URL(string: src)
        else { return nil }
        let alt = extractAttr("alt", from: imgTag)
        return .image(url: url, alt: alt)
    }

    // MARK: Inline HTML → AttributedString

    static func parseInlineHTML(_ html: String) -> AttributedString {
        var result = AttributedString()

        // Split into text segments and tags/entities
        let pattern = #"(<[^>]+>|&(?:#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(html)
        }

        var isBold = false
        var isItalic = false
        var isCode = false
        var currentHref: String? = nil
        var pos = html.startIndex
        let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }

            // Text before this tag/entity
            if pos < range.lowerBound {
                let text = String(html[pos..<range.lowerBound])
                result.append(makeRun(text, bold: isBold, italic: isItalic, code: isCode, href: currentHref))
            }

            let token = String(html[range])
            if token.hasPrefix("&") {
                // HTML entity
                let decoded = decodeEntity(token)
                result.append(makeRun(decoded, bold: isBold, italic: isItalic, code: isCode, href: currentHref))
            } else {
                // Tag
                processTag(token, bold: &isBold, italic: &isItalic, code: &isCode, href: &currentHref)
            }

            pos = range.upperBound
        }

        // Trailing text
        if pos < html.endIndex {
            let text = String(html[pos...])
            result.append(makeRun(text, bold: isBold, italic: isItalic, code: isCode, href: currentHref))
        }

        return result
    }

    private static func makeRun(_ text: String, bold: Bool, italic: Bool, code: Bool, href: String?) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        var attr = AttributedString(text)
        let range = attr.startIndex..<attr.endIndex

        let serifBody: Font = .system(.body, design: .serif)
        if code {
            attr[range].font = .body.monospaced()
        } else {
            switch (bold, italic) {
            case (true, true):  attr[range].font = serifBody.bold().italic()
            case (true, false): attr[range].font = serifBody.bold()
            case (false, true): attr[range].font = serifBody.italic()
            default:            attr[range].font = serifBody
            }
        }

        if let href, let url = URL(string: href) {
            attr[range].link = url
        }

        return attr
    }

    private static func processTag(
        _ tag: String,
        bold: inout Bool,
        italic: inout Bool,
        code: inout Bool,
        href: inout String?
    ) {
        let lower = tag.lowercased()

        if lower == "<strong>" || lower == "<b>" { bold = true }
        else if lower == "</strong>" || lower == "</b>" { bold = false }
        else if lower == "<em>" || lower == "<i>" { italic = true }
        else if lower == "</em>" || lower == "</i>" { italic = false }
        else if lower == "<code>" { code = true }
        else if lower == "</code>" { code = false }
        else if lower == "</a>" { href = nil }
        else if lower.hasPrefix("<a ") {
            href = extractAttr("href", from: tag)
        }
        // <br> → newline character appended by caller via makeRun is not ideal;
        // handle it by inserting directly
    }

    // MARK: Helpers

    private static func leadingTagName(_ html: String) -> String {
        let pattern = #"^<([a-zA-Z][a-zA-Z0-9]*)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html)
        else { return "" }
        return String(html[r]).lowercased()
    }

    private static func extractInnerHTML(_ html: String, tag: String) -> String {
        let pattern = "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html)
        else { return html.strippedHTML }
        return String(html[r])
    }

    private static func extractAttr(_ name: String, from tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        let r1 = Range(m.range(at: 1), in: tag)
        let r2 = Range(m.range(at: 2), in: tag)
        return r1.map { String(tag[$0]) } ?? r2.map { String(tag[$0]) }
    }

    private static func decodeEntity(_ entity: String) -> String {
        // Delegate to the shared extension via a tiny wrapper
        entity.strippedHTML
    }

    private static func removeParsedNoiseTags(_ html: String) -> String {
        html
            .replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "(?is)<(script|style|svg|noscript|iframe|form|nav|header|footer|aside)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
    }
}

// MARK: - Rich Article Content View

struct RichArticleContentView: View {
    let html: String

    @State private var blocks: [ContentBlock]? = nil

    var body: some View {
        Group {
            if let blocks {
                if blocks.isEmpty {
                    emptyContent
                } else {
                    renderedBlocks(blocks)
                }
            } else {
                loadingPlaceholder
            }
        }
        .task(id: html) {
            let parsed = HTMLBlockParser.parse(html)
            blocks = parsed
        }
    }

    // MARK: Block Renderer

    @ViewBuilder
    private func renderedBlocks(_ blocks: [ContentBlock]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .textSelection(.enabled)

        case .heading(let level, let text):
            Text(text)
                .font(headingFont(for: level))
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 12 : 6)
                .textSelection(.enabled)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                Text(text)
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .padding(12)
            }
            .background(Color.platformSecondaryFill, in: RoundedRectangle(cornerRadius: 8))

        case .image(let url, let alt):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    EmptyView()
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.platformTertiaryFill)
                        .frame(height: 160)
                @unknown default:
                    EmptyView()
                }
            }
            .accessibilityLabel(alt ?? "Image")

        case .unorderedList(let items):
            listView(items: items, ordered: false)

        case .orderedList(let items):
            listView(items: items, ordered: true)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func listView(items: [AttributedString], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(item)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 14)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyContent: some View {
        Text("This article didn't include readable inline text. Open it in your browser for the full version.")
            .font(.body)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .textSelection(.enabled)
    }

    // MARK: Helpers

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}
