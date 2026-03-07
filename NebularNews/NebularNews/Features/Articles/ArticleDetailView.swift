import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState

    let articleId: String

    @Query private var articles: [Article]
    @State private var isEnriching = false
    @State private var showTagPicker = false
    @State private var showReactionSheet = false

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

                        // AI Enrichment section (score, summary, key points)
                        aiEnrichmentSection(article)

                        // Tags
                        tagSection(article)

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

                        // Analyze with AI (on-demand)
                        if article.aiProcessedAt == nil && appState.hasAnthropicKey {
                            Button {
                                Task { await enrichArticle(article) }
                            } label: {
                                if isEnriching {
                                    ProgressView()
                                } else {
                                    Label("Analyze", systemImage: "brain")
                                }
                            }
                            .disabled(isEnriching)
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

                        // Reaction
                        Button {
                            showReactionSheet = true
                        } label: {
                            Label(
                                "React",
                                systemImage: reactionIcon(for: article.reactionValue)
                            )
                            .foregroundStyle(reactionColor(for: article.reactionValue))
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
                .sheet(isPresented: $showTagPicker) {
                    TagPickerSheet(article: article)
                }
                .sheet(isPresented: $showReactionSheet) {
                    ReactionSheet(article: article)
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
            // Title + score badge
            HStack(alignment: .top) {
                Text(article.title ?? "Untitled")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if article.score != nil {
                    ScoreBadge(score: article.score)
                }
            }

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

    // MARK: - Tags

    @ViewBuilder
    private func tagSection(_ article: Article) -> some View {
        let tags = article.tags ?? []

        HStack(spacing: 8) {
            if !tags.isEmpty {
                ForEach(tags, id: \.id) { tag in
                    TagPill(name: tag.name, colorHex: tag.colorHex)
                }
            }

            Button {
                showTagPicker = true
            } label: {
                Label(tags.isEmpty ? "Add Tags" : "Edit", systemImage: "tag")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Reaction Helpers

    private func reactionIcon(for value: Int?) -> String {
        switch value {
        case 1: "hand.thumbsup.fill"
        case -1: "hand.thumbsdown.fill"
        default: "hand.thumbsup"
        }
    }

    private func reactionColor(for value: Int?) -> Color {
        switch value {
        case 1: .green
        case -1: .red
        default: .primary
        }
    }

    // MARK: - AI Enrichment Section

    @ViewBuilder
    private func aiEnrichmentSection(_ article: Article) -> some View {
        if article.aiProcessedAt != nil {
            VStack(alignment: .leading, spacing: 12) {
                // Score explanation
                if let score = article.score {
                    HStack(spacing: 8) {
                        ScoreBadge(score: score)
                        Text(article.displayScoreLabel)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.forScore(score))
                    }

                    if let explanation = article.scoreExplanation, !explanation.isEmpty {
                        DisclosureGroup("Why this score") {
                            Text(explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                // Summary
                if let summary = article.summaryText, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Summary", systemImage: "text.alignleft")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(summary)
                            .font(.subheadline)
                            .lineSpacing(3)
                    }
                }

                // Key points
                let points = article.keyPoints
                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Key Points", systemImage: "list.bullet")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(point)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    // MARK: - On-Demand AI Enrichment

    private func enrichArticle(_ article: Article) async {
        guard let apiKey = appState.keychain.get(forKey: KeychainManager.Key.anthropicApiKey) else { return }

        isEnriching = true

        let html = article.contentHtml ?? article.excerpt ?? ""
        let text = html.strippedHTML
        guard !text.isEmpty else {
            isEnriching = false
            return
        }

        let snapshot = ArticleSnapshot(
            id: article.id,
            title: article.title,
            contentText: text,
            canonicalUrl: article.canonicalUrl,
            feedTitle: article.feed?.title
        )

        let client = AnthropicClient(apiKey: apiKey)
        let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
        let enricher = AIEnrichmentService(client: client, articleRepo: articleRepo)
        let settingsRepo = LocalSettingsRepository(modelContainer: modelContext.container)
        let settings = await settingsRepo.get()

        _ = await enricher.enrichArticle(
            snapshot: snapshot,
            userProfile: settings?.userProfilePrompt,
            scoringModel: settings?.scoringModel ?? "claude-haiku-4-5-20251001",
            summaryModel: settings?.defaultModel ?? "claude-haiku-4-5-20251001",
            summaryStyle: settings?.summaryStyle ?? "concise"
        )

        isEnriching = false
        // @Query automatically picks up the changes from updateAIFields()
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
            Text(html.strippedHTML)
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
}
