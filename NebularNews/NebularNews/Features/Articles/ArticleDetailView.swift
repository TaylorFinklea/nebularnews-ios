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
    @Query private var tagSuggestions: [ArticleTagSuggestion]
    @State private var isEnriching = false
    @State private var showTagPicker = false
    @State private var showReactionSheet = false
    @State private var scrollOffset: CGFloat = 0

    init(articleId: String) {
        self.articleId = articleId
        _articles = Query(
            filter: #Predicate<Article> { $0.id == articleId },
            sort: [SortDescriptor(\Article.publishedAt)]
        )
        _tagSuggestions = Query(
            filter: #Predicate<ArticleTagSuggestion> {
                $0.articleId == articleId && $0.dismissedAt == nil
            },
            sort: [SortDescriptor(\ArticleTagSuggestion.createdAt)]
        )
    }

    private var article: Article? { articles.first }
    private var palette: NebularPalette { NebularPalette.forColorScheme(colorScheme) }

    var body: some View {
        Group {
            if let article {
                immersiveReader(article)
                    .sheet(isPresented: $showTagPicker) {
                        TagPickerSheet(article: article)
                    }
                    .sheet(isPresented: $showReactionSheet) {
                        ReactionSheet(article: article)
                    }
                    .onAppear {
                        let shouldSave = article.isDismissed || !article.isRead
                        if article.isDismissed { article.clearDismissal() }
                        if !article.isRead { article.markRead() }
                        if shouldSave { try? modelContext.save() }
                    }
                    .task(id: article.id) {
                        await ensureAutomaticEnrichment(for: article)
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
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Immersive Reader Layout

    @ViewBuilder
    private func immersiveReader(_ article: Article) -> some View {
        NebularScreen(emphasis: .immersive) {
            ScrollView {
                VStack(spacing: 0) {
                    // Scroll offset tracker
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("immersiveScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    // Parallax hero image
                    ImmersiveHeroImage(article: article, scrollOffset: scrollOffset)

                    // Content cards overlapping the hero bottom
                    VStack(spacing: 16) {
                        immersiveHeader(article)
                        fitSection(article)
                        summarySection(article)
                        keyPointsSection(article)
                        contentSection(article)
                        tagSection(article)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, -32)
                    .padding(.bottom, 40)
                }
            }
            .coordinateSpace(name: "immersiveScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
        .toolbar {
            articleToolbar(article)
        }
    }

    // MARK: - Immersive Header

    @ViewBuilder
    private func immersiveHeader(_ article: Article) -> some View {
        GlassCard(cornerRadius: 28, style: .raised, tintColor: headerAccentColor(for: article)) {
            VStack(alignment: .leading, spacing: 14) {
                // Feed source + score
                HStack(spacing: 8) {
                    if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                        Label(feedTitle, systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.primary)
                    }

                    Spacer()

                    if article.hasReadyScore, let score = article.displayedScore {
                        ScoreBadge(score: score)
                    }
                }

                // Title
                Text(article.title ?? "Untitled")
                    .font(NebularTypography.heroTitle)
                    .fixedSize(horizontal: false, vertical: true)

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
            }
            .background(alignment: .topTrailing) {
                NebularHeaderHalo(color: headerAccentColor(for: article))
                    .offset(x: 44, y: -52)
            }
        }
    }

    // MARK: - Fit Section

    @ViewBuilder
    private func fitSection(_ article: Article) -> some View {
        if article.hasReadyScore, let score = article.displayedScore {
            GlassCard(cornerRadius: 22, style: .standard, tintColor: Color.forScore(score)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ScoreBadge(score: score)
                        Text("Algorithmic fit")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.forScore(score))
                    }

                    if let explanation = article.displayedScoreExplanation, !explanation.isEmpty {
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
            }
        } else if article.isLearningScore {
            GlassCard(cornerRadius: 22, style: .standard, tintColor: .purple) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Learning", systemImage: "sparkles")
                        .font(.subheadline.bold())
                    Text("Not enough preference signals yet. React to articles or refine tags to improve fit scoring.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(_ article: Article) -> some View {
        let summary = article.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPending = shouldShowSummaryPlaceholder(for: article)

        if (summary?.isEmpty == false) || isPending {
            GlassCard(cornerRadius: 22, style: .standard, tintColor: palette.primary) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label("Summary", systemImage: "text.alignleft")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        if isPending {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        }
                    }

                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .lineSpacing(3)
                    } else {
                        pendingSummaryPlaceholder
                    }
                }
            }
        }
    }

    // MARK: - Key Points

    @ViewBuilder
    private func keyPointsSection(_ article: Article) -> some View {
        let points = article.keyPoints
        let isPending = shouldShowKeyPointsPlaceholder(for: article)

        if !points.isEmpty || isPending {
            GlassCard(cornerRadius: 22, style: .standard, tintColor: Color.forScore(4)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Label("Key Points", systemImage: "list.bullet")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        if isPending {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        }
                    }

                    if !points.isEmpty {
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(point)
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        pendingKeyPointsPlaceholder
                    }
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentSection(_ article: Article) -> some View {
        GlassCard(cornerRadius: 22, style: .standard, tintColor: palette.primary) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Article text", systemImage: "doc.text")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                articleContent(article)
            }
        }
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

    // MARK: - Tags

    @ViewBuilder
    private func tagSection(_ article: Article) -> some View {
        let tags = article.tags ?? []

        GlassCard(cornerRadius: 22, style: .standard) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Tags", systemImage: "tag")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags, id: \.id) { tag in
                                TagPill(name: tag.name, colorHex: tag.colorHex)
                            }
                        }
                    }
                }

                if !tagSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Suggested Tags", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ForEach(tagSuggestions, id: \.id) { suggestion in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                        .font(.subheadline.weight(.semibold))
                                    if let confidence = suggestion.confidence {
                                        Text("\(Int((confidence * 100).rounded()))% confidence")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 8)

                                Button("Accept") {
                                    acceptTagSuggestion(suggestion)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Dismiss", role: .destructive) {
                                    dismissTagSuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Button {
                    showTagPicker = true
                } label: {
                    Label(tags.isEmpty ? "Add Tags" : "Edit Tags", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Floating Bottom Toolbar

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
                toggleReadingList(for: article)
            } label: {
                toolbarLabel(
                    article.isInReadingList ? "Remove from Reading List" : "Add to Reading List",
                    systemImage: article.isInReadingList ? "bookmark.fill" : "bookmark",
                    tint: article.isInReadingList ? palette.primary : .secondary
                )
            }
            .accessibilityLabel(article.isInReadingList ? "Remove from Reading List" : "Add to Reading List")
            Spacer()

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

            Spacer()
            overflowMenu(article)
        }
    }

    private func overflowMenu(_ article: Article) -> some View {
        Menu {
            if let url = articleURL(for: article) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Button(
                article.isRead ? "Mark Unread" : "Mark Read",
                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
            ) {
                toggleReadState(for: article)
            }

            Button {
                Task { await enrichArticle(article, target: .automatic) }
            } label: {
                Label(isEnriching ? "Summarizing…" : "Summarize", systemImage: "text.alignleft")
            }
            .disabled(isEnriching)

            if appState.hasAnthropicKey {
                Button {
                    Task { await enrichArticle(article, target: .anthropic) }
                } label: {
                    Label(
                        isEnriching ? "Regenerating…" : "Regenerate with Anthropic",
                        systemImage: "brain"
                    )
                }
                .disabled(isEnriching)
            }

            if appState.hasOpenAIKey {
                Button {
                    Task { await enrichArticle(article, target: .openAI) }
                } label: {
                    Label(
                        isEnriching ? "Regenerating…" : "Regenerate with OpenAI",
                        systemImage: "sparkles.rectangle.stack"
                    )
                }
                .disabled(isEnriching)
            }
        } label: {
            toolbarLabel("More", systemImage: "ellipsis")
        }
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

    // MARK: - Helpers

    @ViewBuilder
    private var pendingSummaryPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generating automatically with on-device AI when available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Placeholder summary sentence for the article content.")
                Text("Additional placeholder detail appears once generation finishes.")
                Text("This card will update in place without manual action.")
            }
            .font(.subheadline)
            .lineSpacing(3)
            .redacted(reason: .placeholder)
        }
    }

    @ViewBuilder
    private var pendingKeyPointsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key points are being generated automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(0..<4, id: \.self) { _ in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Placeholder key point for the generated summary.")
                        .font(.subheadline)
                }
                .redacted(reason: .placeholder)
            }
        }
    }

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
        case 1: "Liked"
        case -1: "Disliked"
        default: "Not set"
        }
    }

    private func toggleReadState(for article: Article) {
        if article.isRead { article.markUnread() } else { article.markRead() }
        try? modelContext.save()
    }

    private func toggleReadingList(for article: Article) {
        article.toggleReadingList()
        try? modelContext.save()
    }

    private func articleURL(for article: Article) -> URL? {
        guard let urlString = article.canonicalUrl else { return nil }
        return URL(string: urlString)
    }

    private func headerAccentColor(for article: Article) -> Color {
        if article.hasReadyScore, let score = article.displayedScore {
            return Color.forScore(score)
        }
        if article.isLearningScore { return .purple }
        return palette.primary
    }

    private func shouldShowSummaryPlaceholder(for article: Article) -> Bool {
        hasSummarizableContent(article) && ((article.summaryText?.isEmpty ?? true) || isEnriching)
    }

    private func shouldShowKeyPointsPlaceholder(for article: Article) -> Bool {
        hasSummarizableContent(article) && (article.keyPoints.isEmpty || isEnriching)
    }

    private func needsAutomaticEnrichment(for article: Article) -> Bool {
        hasSummarizableContent(article) && ((article.summaryText?.isEmpty ?? true) || article.keyPoints.isEmpty)
    }

    private func hasSummarizableContent(_ article: Article) -> Bool {
        let html = article.contentHtml ?? article.excerpt ?? ""
        return !html.strippedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func snapshotForEnrichment(_ article: Article) -> ArticleSnapshot? {
        let html = article.contentHtml ?? article.excerpt ?? ""
        let text = html.strippedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return ArticleSnapshot(
            id: article.id,
            title: article.title,
            contentText: text,
            canonicalUrl: article.canonicalUrl,
            feedTitle: article.feed?.title
        )
    }

    private func ensureAutomaticEnrichment(for article: Article) async {
        guard needsAutomaticEnrichment(for: article),
              !isEnriching
        else {
            return
        }

        await enrichArticle(article, target: .automatic)
    }

    // MARK: - AI Enrichment

    private func enrichArticle(_ article: Article, target: AIExplicitGenerationTarget) async {
        guard !isEnriching,
              let snapshot = snapshotForEnrichment(article)
        else {
            return
        }

        isEnriching = true
        defer { isEnriching = false }
        let enricher = AIEnrichmentService(
            modelContainer: modelContext.container,
            keychainService: appState.configuration.keychainService
        )
        let settingsRepo = LocalSettingsRepository(modelContainer: modelContext.container)
        let settings = await settingsRepo.get()

        _ = await enricher.enrichArticle(
            snapshot: snapshot,
            summaryStyle: settings?.summaryStyle ?? "concise",
            target: target
        )
    }

    private func acceptTagSuggestion(_ suggestion: ArticleTagSuggestion) {
        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: appState.configuration.keychainService
            )
            await service.acceptTagSuggestion(articleID: articleId, suggestionID: suggestion.id)
        }
    }

    private func dismissTagSuggestion(_ suggestion: ArticleTagSuggestion) {
        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: appState.configuration.keychainService
            )
            await service.dismissTagSuggestion(articleID: articleId, suggestionID: suggestion.id)
        }
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Simple HTML → Plain Text Renderer

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
