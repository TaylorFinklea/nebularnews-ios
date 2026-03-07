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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    articleActionBar(article)
                }
                .sheet(isPresented: $showTagPicker) {
                    TagPickerSheet(article: article)
                }
                .sheet(isPresented: $showReactionSheet) {
                    ReactionSheet(article: article)
                }
                .onAppear {
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

    @ViewBuilder
    private func articleActionBar(_ article: Article) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    article.isRead.toggle()
                    article.readAt = article.isRead ? Date() : nil
                    try? modelContext.save()
                } label: {
                    actionIcon(
                        article.isRead ? "envelope.badge" : "envelope.open",
                        color: palette.primary
                    )
                }
                .accessibilityLabel(article.isRead ? "Mark Unread" : "Mark Read")

                if appState.hasAnthropicKey && ((article.summaryText?.isEmpty != false) || article.keyPoints.isEmpty) {
                    Button {
                        Task { await enrichArticle(article) }
                    } label: {
                        Group {
                            if isEnriching {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(palette.primary)
                                    .frame(width: 48, height: 48)
                            } else {
                                actionIcon("text.alignleft", color: palette.primary)
                            }
                        }
                    }
                    .disabled(isEnriching)
                    .accessibilityLabel("Summarize")
                }

                if let urlString = article.canonicalUrl,
                   let url = URL(string: urlString) {
                    Button {
                        openURL(url)
                    } label: {
                        actionIcon("safari", color: palette.primary)
                    }
                    .accessibilityLabel("Open in Browser")
                }

                Button {
                    showReactionSheet = true
                } label: {
                    actionIcon(
                        reactionIcon(for: article.reactionValue),
                        color: reactionColor(for: article.reactionValue)
                    )
                }
                .accessibilityLabel("React")
            }
            .buttonStyle(ArticleActionBarButtonStyle())
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .modifier(ArticleActionBarCapsuleBackground())

            if let urlString = article.canonicalUrl,
               let url = URL(string: urlString) {
                ShareLink(item: url) {
                    actionIcon("square.and.arrow.up", color: palette.primary)
                }
                .buttonStyle(ArticleActionBarButtonStyle())
                .modifier(ArticleActionButtonBackground())
                .accessibilityLabel("Share")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func actionIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
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

private struct ArticleActionBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ArticleActionBarCapsuleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        glassContent(content)
            .shadow(color: palette.shadow.opacity(0.34), radius: 20, y: 10)
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
                .tint(palette.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                .overlay(Capsule().strokeBorder(palette.surfaceBorder.opacity(0.9)))
        } else {
            fallbackContent(content)
        }
#else
        fallbackContent(content)
#endif
    }

    private func fallbackContent(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .background(palette.surfaceStrong, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.surfaceBorder.opacity(0.9)))
    }
}

private struct ArticleActionButtonBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        glassContent(content)
            .shadow(color: palette.shadow.opacity(0.28), radius: 18, y: 10)
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .tint(palette.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        } else {
            fallbackContent(content)
        }
#else
        fallbackContent(content)
#endif
    }

    private func fallbackContent(_ content: Content) -> some View {
        content
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .background(palette.surfaceStrong, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.surfaceBorder.opacity(0.9)))
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
