import SwiftUI
import SwiftData
import os
import NebularNewsKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
    category: "ArticleDetail"
)

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
                        if shouldSave {
                            saveContext()
                            syncStandaloneState(for: article.id)
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
        .safeAreaInset(edge: .bottom) {
            articleActionTray(article)
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

                if let creditLine = article.fallbackImageCreditLine,
                   let profileURLString = article.fallbackImagePhotographerProfileUrl,
                   let profileURL = URL(string: profileURLString) {
                    Link(destination: profileURL) {
                        Label(creditLine, systemImage: "camera")
                            .font(.caption)
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
                        pendingSummaryPlaceholder(article)
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
                HStack(spacing: 8) {
                    Label(article.isKnownPreviewOnlySource ? "Article preview" : "Article text", systemImage: "doc.text")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                articleContent(article)
            }
        }
    }

    @ViewBuilder
    private func articleContent(_ article: Article) -> some View {
        let isPendingContent = article.contentPreparationStatusValue == .pending

        if let html = article.contentHtml, !html.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if isPendingContent {
                    Text("Pulling the full article text now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if article.contentPreparationStatusValue == .failed || article.contentPreparationStatusValue == .blocked {
                    Text(contentFallbackMessage(for: article, excerptOnly: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HTMLTextView(html: html)
            }
        } else if let excerpt = article.excerpt, !excerpt.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if isPendingContent {
                    Text("Pulling the full article text now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if article.contentPreparationStatusValue == .failed || article.contentPreparationStatusValue == .blocked {
                    Text(contentFallbackMessage(for: article, excerptOnly: true))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(excerpt)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        } else {
            VStack(spacing: 12) {
                if isPendingContent {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Fetching the full article text.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No content available. Open in browser to read the full article.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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

    private func contentFallbackMessage(for article: Article, excerptOnly: Bool) -> String {
        if article.isKnownPreviewOnlySource {
            return excerptOnly
                ? "This publisher only exposes a short RSS preview here. Open in browser to read the full article."
                : "This publisher only exposes the feed-provided preview here. Open in browser to read the full article."
        }

        return excerptOnly
            ? "This article is showing the feed excerpt because full-text extraction wasn't available."
            : "This article is showing the feed-provided version because full-text extraction wasn't available."
    }

    // MARK: - Bottom Action Tray

    @ViewBuilder
    private func articleActionTray(_ article: Article) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                articleActionTrayContent(article)
            }
        } else {
            articleActionTrayContent(article)
        }
    }

    private func articleActionTrayContent(_ article: Article) -> some View {
        HStack(spacing: 18) {
            if let url = articleURL(for: article) {
                Button {
                    openURL(url)
                } label: {
                    articleTraySideIcon(systemImage: "safari")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open in Browser")
            } else {
                Color.clear
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
            }

            articleActionCluster(article)

            overflowMenu(article)
                .accessibilityLabel("More")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func articleActionCluster(_ article: Article) -> some View {
        HStack(spacing: 2) {
            Button {
                toggleReadingList(for: article)
            } label: {
                articleClusterIcon(
                    systemImage: article.isInReadingList ? "bookmark.fill" : "bookmark",
                    tint: article.isInReadingList ? palette.primary : .secondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(article.isInReadingList ? "Remove from Reading List" : "Add to Reading List")

            Button {
                Task { await enrichArticle(articleId: article.id, target: .automatic) }
            } label: {
                articleClusterIcon(
                    systemImage: isEnriching ? "sparkles" : "text.alignleft",
                    tint: isEnriching ? palette.primary : .secondary,
                    showsProgress: isEnriching
                )
            }
            .buttonStyle(.plain)
            .disabled(isEnriching)
            .accessibilityLabel(isEnriching ? "Summarizing" : "Summarize")

            Button {
                showReactionSheet = true
            } label: {
                articleClusterIcon(
                    systemImage: reactionIcon(for: article.reactionValue),
                    tint: reactionToolbarTint(for: article.reactionValue)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("React")
            .accessibilityValue(reactionAccessibilityValue(for: article.reactionValue))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(ArticleTrayCapsuleBackground())
        .accessibilityElement(children: .contain)
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
                Task { await enrichArticle(articleId: article.id, target: .automatic) }
            } label: {
                Label(isEnriching ? "Summarizing…" : "Summarize", systemImage: "text.alignleft")
            }
            .disabled(isEnriching)

            if appState.hasAnthropicKey {
                Button {
                    Task { await enrichArticle(articleId: article.id, target: .anthropic) }
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
                    Task { await enrichArticle(articleId: article.id, target: .openAI) }
                } label: {
                    Label(
                        isEnriching ? "Regenerating…" : "Regenerate with OpenAI",
                        systemImage: "sparkles.rectangle.stack"
                    )
                }
                .disabled(isEnriching)
            }
        } label: {
            articleTraySideIcon(systemImage: "ellipsis")
        }
    }

    private func articleTraySideIcon(systemImage: String, tint: Color = .secondary) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .modifier(ArticleTrayCircleBackground())
    }

    @ViewBuilder
    private func articleClusterIcon(
        systemImage: String,
        tint: Color = .secondary,
        showsProgress: Bool = false
    ) -> some View {
        Group {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 52, height: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pendingSummaryPlaceholder(_ article: Article) -> some View {
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

            HStack {
                Spacer()
                Button {
                    Task { await enrichArticle(articleId: article.id, target: .automatic) }
                } label: {
                    Label(isEnriching ? "Generating…" : "Generate Now", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isEnriching)
            }
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
        saveContext()
        syncStandaloneState(for: article.id)
    }

    private func toggleReadingList(for article: Article) {
        article.toggleReadingList()
        saveContext()
        syncStandaloneState(for: article.id)
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save model context: \(error.localizedDescription, privacy: .public)")
        }
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
        !article.bestAvailableContentText.isEmpty &&
        (((article.summaryText?.isEmpty ?? true) && article.enrichmentPreparationStatusValue == .pending) || isEnriching)
    }

    private func shouldShowKeyPointsPlaceholder(for article: Article) -> Bool {
        !article.bestAvailableContentText.isEmpty &&
        ((article.keyPoints.isEmpty && article.enrichmentPreparationStatusValue == .pending) || isEnriching)
    }

    // MARK: - AI Enrichment

    private func enrichArticle(articleId: String, target: AIExplicitGenerationTarget) async {
        guard !isEnriching else {
            return
        }

        let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
        guard let snapshot = await articleRepo.enrichmentSnapshot(id: articleId) else {
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

    private func syncStandaloneState(for articleID: String) {
        Task {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            do {
                try await articleRepo.syncStandaloneUserState(id: articleID)
            } catch {
                logger.error("Failed to sync state for \(articleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Scroll Offset Tracking

private struct ArticleTrayCircleBackground: ViewModifier {
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
    }
}

private struct ArticleTrayCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
    }
}

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
