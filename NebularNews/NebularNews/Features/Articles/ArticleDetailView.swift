import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let articleId: String

    @Query private var articles: [Article]

    init(articleId: String) {
        self.articleId = articleId
        _articles = Query(
            filter: #Predicate<Article> { $0.id == articleId },
            sort: [SortDescriptor(\Article.publishedAt)]
        )
    }

    private var article: Article? { articles.first }

    var body: some View {
        Group {
            if let article {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        articleHeader(article)

                        Divider()

                        // Content
                        articleContent(article)
                    }
                    .padding()
                }
                .navigationTitle(article.feed?.title ?? "Article")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        // Mark read/unread
                        Button {
                            article.isRead.toggle()
                            article.readAt = article.isRead ? Date() : nil
                            try? modelContext.save()
                        } label: {
                            Label(
                                article.isRead ? "Mark Unread" : "Mark Read",
                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                            )
                        }

                        Spacer()

                        // Open in browser
                        if let urlString = article.canonicalUrl,
                           let url = URL(string: urlString) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open in Browser", systemImage: "safari")
                            }
                        }

                        Spacer()

                        // Share
                        if let urlString = article.canonicalUrl,
                           let url = URL(string: urlString) {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .onAppear {
                    // Auto-mark as read when opened
                    if !article.isRead {
                        article.isRead = true
                        article.readAt = Date()
                        try? modelContext.save()
                    }
                }
            } else {
                ContentUnavailableView(
                    "Article Not Found",
                    systemImage: "doc.text",
                    description: Text("This article may have been removed.")
                )
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func articleHeader(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(article.title ?? "Untitled")
                .font(.title2)
                .fontWeight(.bold)

            // Author + date
            HStack(spacing: 12) {
                if let author = article.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let date = article.publishedAt {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Feed name
            if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                Label(feedTitle, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func articleContent(_ article: Article) -> some View {
        if let html = article.contentHtml, !html.isEmpty {
            // Render HTML content as attributed string
            HTMLTextView(html: html)
        } else if let excerpt = article.excerpt, !excerpt.isEmpty {
            Text(excerpt)
                .font(.body)
                .lineSpacing(4)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No content available. Open in browser to read the full article.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }
}

// MARK: - Simple HTML → AttributedString renderer

private struct HTMLTextView: View {
    let html: String

    var body: some View {
        if let attributed = renderHTML(html) {
            Text(attributed)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            // Fallback: strip tags and show plain text
            Text(stripHTML(html))
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func renderHTML(_ html: String) -> AttributedString? {
        // Wrap in basic styling for readability
        let styled = """
        <style>
            body { font-family: -apple-system; font-size: 17px; line-height: 1.5; }
            img { max-width: 100%; height: auto; }
            a { color: #007AFF; }
            pre, code { font-family: Menlo; font-size: 14px; background: #f5f5f5; padding: 4px; }
        </style>
        \(html)
        """

        guard let data = styled.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let nsAttr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }

        return try? AttributedString(nsAttr, including: \.uiKit)
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
