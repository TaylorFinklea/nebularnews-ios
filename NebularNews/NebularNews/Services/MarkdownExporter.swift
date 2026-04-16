import Foundation

struct MarkdownExporter {

    /// Export a single article with its enrichments, highlights, and annotation.
    static func exportArticle(
        article: CompanionArticle,
        summary: CompanionArticleSummary?,
        keyPoints: CompanionKeyPoints?,
        tags: [CompanionTag],
        highlights: [CompanionHighlight],
        annotation: CompanionAnnotation?,
        sourceName: String?
    ) -> String {
        var lines: [String] = []

        // Title
        lines.append("# \(article.title ?? "Untitled")")
        lines.append("")

        // Metadata
        var meta: [String] = []
        if let source = sourceName { meta.append("**Source**: \(source)") }
        if let author = article.author { meta.append("**Author**: \(author)") }
        if let publishedAt = article.publishedAt {
            let date = Date(timeIntervalSince1970: Double(publishedAt) / 1000)
            meta.append("**Date**: \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " | "))
            lines.append("")
        }

        if !tags.isEmpty {
            lines.append("**Tags**: \(tags.map(\.name).joined(separator: ", "))")
            lines.append("")
        }

        if let url = article.canonicalUrl {
            lines.append("**URL**: \(url)")
            lines.append("")
        }

        // Annotation
        if let annotation, !annotation.content.isEmpty {
            lines.append("## Notes")
            lines.append("")
            lines.append(annotation.content)
            lines.append("")
        }

        // Highlights
        if !highlights.isEmpty {
            lines.append("## Highlights")
            lines.append("")
            for highlight in highlights {
                lines.append("> \(highlight.selectedText)")
                if let note = highlight.note, !note.isEmpty {
                    lines.append("*\(note)*")
                }
                lines.append("")
            }
        }

        // AI Summary
        if let summary = summary?.summaryText, !summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
            lines.append("")
        }

        // Key Points
        if let kpJson = keyPoints?.keyPointsJson,
           let data = kpJson.data(using: .utf8),
           let points = try? JSONDecoder().decode([String].self, from: data),
           !points.isEmpty {
            lines.append("## Key Points")
            lines.append("")
            for point in points {
                lines.append("- \(point)")
            }
            lines.append("")
        }

        // Excerpt (if no content available)
        if let excerpt = article.excerpt, !excerpt.isEmpty,
           article.contentHtml == nil, article.contentText == nil {
            lines.append("## Excerpt")
            lines.append("")
            lines.append(excerpt)
            lines.append("")
        }

        lines.append("---")
        lines.append("*Exported from NebularNews*")

        return lines.joined(separator: "\n")
    }

    /// Export all articles in a collection.
    static func exportCollection(
        name: String,
        articles: [CompanionArticleListItem]
    ) -> String {
        var lines: [String] = []

        lines.append("# \(name)")
        lines.append("")
        lines.append("\(articles.count) article\(articles.count == 1 ? "" : "s")")
        lines.append("")
        lines.append("---")
        lines.append("")

        for article in articles {
            lines.append("## \(article.title ?? "Untitled")")
            if let source = article.sourceName {
                lines.append("*\(source)*")
            }
            if let summary = article.summaryText, !summary.isEmpty {
                lines.append("")
                lines.append(summary)
            }
            if let url = article.canonicalUrl {
                lines.append("")
                lines.append("[\(article.title ?? "Read")]()")
                lines.append("URL: \(url)")
            }
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        lines.append("*Exported from NebularNews*")

        return lines.joined(separator: "\n")
    }
}
