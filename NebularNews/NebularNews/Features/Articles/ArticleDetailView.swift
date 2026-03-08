import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
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
    private var palette: NebularPalette { NebularPalette.forColorScheme(colorScheme) }

    var body: some View {
        Group {
            if let article {
                NebularScreen(emphasis: .reading) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            articleHeaderCard(article)
                            fitSection(article)
                            summarySection(article)
                            keyPointsSection(article)
                            contentSection(article)
                        }
                        .padding()
                    }
                }
                .navigationTitle(article.feed?.title ?? "Article")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    articleToolbar(article)
                }
                .sheet(isPresented: $showTagPicker) {
                    TagPickerSheet(article: article)
                }
                .sheet(isPresented: $showReactionSheet) {
                    ReactionSheet(article: article)
                }
                .onAppear {
                    let shouldSave = article.isDismissed || !article.isRead
                    if article.isDismissed {
                        article.clearDismissal()
                    }
                    if !article.isRead {
                        article.markRead()
                    }
                    if shouldSave {
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
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Header + Actions

    @ViewBuilder
    private func articleHeaderCard(_ article: Article) -> some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: headerAccentColor(for: article)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                            Label(feedTitle, systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(article.title ?? "Untitled")
                            .font(.largeTitle.bold())
                            .tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    if article.hasReadyScore, let score = article.score {
                        ScoreBadge(score: score)
                    }
                }

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

                tagSection(article)
            }
            .background(alignment: .topTrailing) {
                NebularHeaderHalo(color: headerAccentColor(for: article))
                    .offset(x: 44, y: -52)
            }
        }
    }

    @ToolbarContentBuilder
    private func articleToolbar(_ article: Article) -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if let url = articleURL(for: article) {
                Button {
                    openURL(url)
                } label: {
                    toolbarLabel("Open in Browser", systemImage: "safari")
                }
                Spacer()
            }

            Button {
                showReactionSheet = true
            } label: {
                toolbarLabel(
                    "React",
                    systemImage: reactionIcon(for: article.reactionValue),
                    tint: reactionToolbarTint(for: article.reactionValue)
                )
            }
            .accessibilityLabel("React")
            .accessibilityValue(reactionAccessibilityValue(for: article.reactionValue))

            if let url = articleURL(for: article) {
                Spacer()
                ShareLink(item: url) {
                    toolbarLabel("Share", systemImage: "square.and.arrow.up")
                }
            }

            Spacer()
            overflowMenu(article)
        }
    }

    private func overflowMenu(_ article: Article) -> some View {
        Menu {
            Button(
                article.isRead ? "Mark Unread" : "Mark Read",
                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
            ) {
                toggleReadState(for: article)
            }

            if appState.hasAnthropicKey && ((article.summaryText?.isEmpty != false) || article.keyPoints.isEmpty) {
                Button {
                    Task { await enrichArticle(article) }
                } label: {
                    Label(isEnriching ? "Summarizing…" : "Summarize", systemImage: "text.alignleft")
                }
                .disabled(isEnriching)
            }
        } label: {
            toolbarLabel("More", systemImage: "ellipsis")
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private func tagSection(_ article: Article) -> some View {
        let tags = article.tags ?? []

        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.id) { tag in
                            TagPill(name: tag.name, colorHex: tag.colorHex)
                        }
                    }
                }
            }

            Button {
                showTagPicker = true
            } label: {
                Label(tags.isEmpty ? "Add Tags" : "Edit Tags", systemImage: "tag")
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
        case 1: Color.forScore(5)
        case -1: palette.danger
        default: palette.primary
        }
    }

    private func reactionToolbarTint(for value: Int?) -> Color {
        switch value {
        case 1, -1:
            return reactionColor(for: value)
        default:
            return .secondary
        }
    }

    private func reactionAccessibilityValue(for value: Int?) -> String {
        switch value {
        case 1:
            return "Liked"
        case -1:
            return "Disliked"
        default:
            return "Not set"
        }
    }

    private func toggleReadState(for article: Article) {
        if article.isRead {
            article.markUnread()
        } else {
            article.markRead()
        }
        try? modelContext.save()
    }

    private func articleURL(for article: Article) -> URL? {
        guard let urlString = article.canonicalUrl else { return nil }
        return URL(string: urlString)
    }

    private func toolbarLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .foregroundStyle(tint)
    }

    private func headerAccentColor(for article: Article) -> Color {
        if article.hasReadyScore, let score = article.score {
            return Color.forScore(score)
        }
        if article.isLearningScore {
            return .purple
        }
        return palette.primary
    }

    // MARK: - Fit + Enrichment Sections

    @ViewBuilder
    private func fitSection(_ article: Article) -> some View {
        if article.hasReadyScore, let score = article.score {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ScoreBadge(score: score)
                    Text("Algorithmic fit")
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
            .modifier(DetailSectionCard(tintColor: Color.forScore(score)))
        } else if article.isLearningScore {
            VStack(alignment: .leading, spacing: 8) {
                Label("Learning", systemImage: "sparkles")
                    .font(.subheadline.bold())
                Text("Not enough preference signals yet. React to articles or refine tags to improve fit scoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .modifier(DetailSectionCard(tintColor: .purple))
        }
    }

    @ViewBuilder
    private func summarySection(_ article: Article) -> some View {
        if let summary = article.summaryText, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.subheadline)
                    .lineSpacing(3)
            }
            .modifier(DetailSectionCard(tintColor: palette.primary))
        }
    }

    @ViewBuilder
    private func keyPointsSection(_ article: Article) -> some View {
        let points = article.keyPoints
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
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
            .modifier(DetailSectionCard(tintColor: Color.forScore(4)))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentSection(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Article text", systemImage: "doc.text")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            articleContent(article)
        }
        .modifier(DetailSectionCard(tintColor: palette.primary))
    }

    @ViewBuilder
    private func articleContent(_ article: Article) -> some View {
        if let html = article.contentHtml, !html.isEmpty {
            HTMLTextView(html: html)
        } else if let excerpt = article.excerpt, !excerpt.isEmpty {
            Text(excerpt)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
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
            .padding(.vertical, 28)
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
            summaryModel: settings?.defaultModel ?? "claude-haiku-4-5-20251001",
            summaryStyle: settings?.summaryStyle ?? "concise"
        )

        isEnriching = false
    }
}

// MARK: - Simple HTML → Plain Text renderer

private struct HTMLTextView: View {
    let html: String

    var body: some View {
        let plainText = renderPlainText(html)

        if plainText.isEmpty {
            Text("This article didn't include readable inline text. Open it in your browser for the full version.")
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            Text(plainText)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func renderPlainText(_ html: String) -> String {
        html
            .replacingOccurrences(
                of: "(?i)<\\s*br\\s*/?\\s*>",
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)<\\s*/\\s*(p|div|section|article|h[1-6]|ul|ol|li|blockquote|tr)\\s*>",
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)<\\s*li\\b[^>]*>",
                with: "• ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "[ \\t\\f\\r]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DetailSectionCard: ViewModifier {
    let tintColor: Color?

    func body(content: Content) -> some View {
        GlassCard(cornerRadius: 22, style: .standard, tintColor: tintColor) {
            content
        }
    }
}
