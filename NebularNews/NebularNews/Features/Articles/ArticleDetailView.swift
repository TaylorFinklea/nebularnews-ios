import SwiftUI
import NebularNewsKit

/// Rich article detail view with AI enrichment, tags, and reactions.
///
/// Ported from the standalone-era `ArticleDetailView`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData `@Query`.
struct ArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let articleId: String

    @State private var payload: CompanionArticleDetailPayload?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showTagPicker = false
    @State private var showReactionSheet = false
    @State private var savingRead = false
    @State private var isSaved = false
    @State private var savingBookmark = false
    @State private var isSummarizing = false
    @State private var pendingTagName = ""
    @State private var savingTag = false
    @State private var acceptingSuggestion: String?
    @State private var scrollProgress: CGFloat = 0

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article...")
            } else if let payload {
                loadedArticleView(payload)
            } else {
                emptyArticleView
            }
        }
        .navigationTitle(payload?.preferredSource?.feedTitle ?? "Article")
        .inlineNavigationBarTitle()
        .refreshable { await loadArticle() }
        .task {
            if payload == nil {
                await loadArticle()
            }
        }
    }

    @ViewBuilder
    private func loadedArticleView(_ payload: CompanionArticleDetailPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageUrl = payload.article.imageUrl, let url = URL(string: imageUrl) {
                    ArticleHeroImage(url: url)
                }

                VStack(alignment: .leading, spacing: 16) {
                    articleHeader(payload)
                    aiEnrichmentSection(payload)
                    tagSection(payload)
                    Divider()
                    articleContent(payload)
                }
                .padding(.horizontal)
            }
            .background(
                GeometryReader { contentGeometry in
                    Color.clear.preference(
                        key: ScrollContentHeightKey.self,
                        value: contentGeometry.frame(in: .named("articleScroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "articleScroll")
        .onPreferenceChange(ScrollContentHeightKey.self) { offset in
            // offset is negative as user scrolls down
            // Approximate: content extends below the visible area
            let clamped = min(max(-offset / max(1, UIScreen.main.bounds.height * 2), 0), 1)
            scrollProgress = clamped
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ProgressView(value: scrollProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .scaleEffect(x: 1, y: 0.5, anchor: .top)
                .opacity(scrollProgress > 0.01 ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: scrollProgress)
        }
        .hideTabBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                topTrailingToolbar(payload)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                bottomToolbar(payload)
            }
        }
        .sheet(isPresented: $showReactionSheet) {
            ReactionSheet(
                currentValue: payload.reaction?.value,
                currentCodes: payload.reaction?.reasonCodes ?? [],
                onSave: { value, codes in
                    Task { await saveReaction(value: value, reasonCodes: codes) }
                },
                onClear: {
                    self.payload?.reaction = nil
                }
            )
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerSheet(
                articleId: articleId,
                currentTags: payload.tags,
                onTagsChanged: { newTags in
                    self.payload?.tags = newTags
                }
            )
        }
    }

    @ViewBuilder
    private func topTrailingToolbar(_ payload: CompanionArticleDetailPayload) -> some View {
        Button {
            Task { await toggleRead() }
        } label: {
            Image(systemName: payload.article.isRead == 1 ? "eye.slash" : "eye")
        }
        .disabled(savingRead)

        Button {
            Task { await toggleSaved() }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
        }
        .disabled(savingBookmark)
    }

    @ViewBuilder
    private func bottomToolbar(_ payload: CompanionArticleDetailPayload) -> some View {
        if let canonicalURL = payload.article.canonicalUrl,
           let url = URL(string: canonicalURL) {
            Link(destination: url) {
                Label("Open", systemImage: "safari")
            }
        }

        Spacer()

        Button {
            Task { await summarize() }
        } label: {
            if isSummarizing {
                ProgressView().controlSize(.small)
            } else {
                Label(
                    payload.summary?.summaryText?.isEmpty == false ? "Re-summarize" : "Summarize",
                    systemImage: "sparkles"
                )
            }
        }
        .disabled(isSummarizing)

        Spacer()

        Button {
            showReactionSheet = true
        } label: {
            Label("React", systemImage: reactionIcon(for: payload.reaction?.value))
                .foregroundStyle(reactionColor(for: payload.reaction?.value))
        }

        Spacer()

        if let canonicalURL = payload.article.canonicalUrl,
           let url = URL(string: canonicalURL) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var emptyArticleView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Article Not Found",
                systemImage: "doc.text",
                description: Text(errorMessage.isEmpty ? "This article may have been removed." : errorMessage)
            )
            if !errorMessage.isEmpty {
                Button("Retry") { Task { await loadArticle() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func articleHeader(_ payload: CompanionArticleDetailPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack(alignment: .top, spacing: 12) {
                Text(payload.article.title ?? "Untitled")
                    .font(.title.weight(.bold))
                    .lineSpacing(2)

                if let score = payload.score?.score {
                    ScoreBadge(score: score)
                }
            }

            // Byline: source · author · date
            VStack(alignment: .leading, spacing: 4) {
                if let feedTitle = payload.preferredSource?.feedTitle, !feedTitle.isEmpty {
                    Text(feedTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    if let author = payload.article.author, !author.isEmpty {
                        Text(author)
                            .foregroundStyle(.secondary)
                    }

                    if payload.article.author != nil && payload.article.publishedAt != nil {
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }

                    if let publishedAt = payload.article.publishedAt {
                        Text(Date(timeIntervalSince1970: Double(publishedAt) / 1000)
                            .formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.tertiary)
                    }

                    if let minutes = estimatedReadingTime(for: payload.article) {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(minutes) min read")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private func tagSection(_ payload: CompanionArticleDetailPayload) -> some View {
        let tags = payload.tags

        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        HStack(spacing: 4) {
                            TagPill(name: tag.name)
                            Button {
                                Task { await removeTag(tag) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Tag suggestions
            if !payload.tagSuggestions.isEmpty {
                HStack(spacing: 6) {
                    Text("Suggested:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(payload.tagSuggestions) { suggestion in
                        Button {
                            Task { await acceptTagSuggestion(suggestion) }
                        } label: {
                            Text(suggestion.name)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.platformTertiaryFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(acceptingSuggestion == suggestion.id)
                    }
                }
            }

            HStack {
                TextField("Add tag", text: $pendingTagName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Add") {
                    Task { await addTag() }
                }
                .disabled(pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingTag)
                .controlSize(.small)

                Button {
                    showTagPicker = true
                } label: {
                    Image(systemName: "tag")
                }
                .controlSize(.small)
            }
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
    private func aiEnrichmentSection(_ payload: CompanionArticleDetailPayload) -> some View {
        let hasAI = payload.summary != nil || payload.score != nil || payload.keyPoints != nil

        if hasAI {
            VStack(alignment: .leading, spacing: 12) {
                // Score explanation
                if let score = payload.score, let scoreValue = score.score {
                    HStack(spacing: 8) {
                        ScoreBadge(score: scoreValue)
                        if let label = score.label, !label.isEmpty {
                            Text(label)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.forScore(scoreValue))
                        }
                    }

                    if let explanation = score.reasonText, !explanation.isEmpty {
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
                if let summary = payload.summary?.summaryText, !summary.isEmpty {
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
                if let keyPoints = payload.keyPoints,
                   let jsonString = keyPoints.keyPointsJson,
                   !jsonString.isEmpty,
                   let data = jsonString.data(using: .utf8),
                   let points = try? JSONDecoder().decode([String].self, from: data),
                   !points.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Key Points", systemImage: "list.bullet")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\u{2022}")
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
    private func articleContent(_ payload: CompanionArticleDetailPayload) -> some View {
        if let html = payload.article.contentHtml, !html.isEmpty {
            RichArticleContentView(html: html)
        } else if let text = payload.article.contentText, !text.isEmpty {
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
                .textSelection(.enabled)
        } else if let excerpt = payload.article.excerpt, !excerpt.isEmpty {
            Text(excerpt)
                .font(.system(.body, design: .serif))
                .lineSpacing(6)
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
            .padding(.top, 40)
        }
    }

    // MARK: - Actions

    private func loadArticle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await appState.supabase.fetchArticle(id: articleId)
            payload = detail
            errorMessage = ""
            isSaved = detail.article.savedAt != nil
            // Auto-mark as read
            if detail.article.isRead != 1 {
                await appState.syncManager?.setRead(articleId: articleId, isRead: true)
                payload?.article.isRead = 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRead() async {
        guard let payload else { return }
        savingRead = true
        let newIsRead = payload.article.isRead != 1
        await appState.syncManager?.setRead(articleId: articleId, isRead: newIsRead)
        self.payload?.article.isRead = newIsRead ? 1 : 0
        savingRead = false
    }

    private func toggleSaved() async {
        savingBookmark = true
        defer { savingBookmark = false }
        if let response = await appState.syncManager?.saveArticle(articleId: articleId, saved: !isSaved) {
            isSaved = response.saved
        }
    }

    private func addTag() async {
        let trimmed = pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savingTag = true
        defer { savingTag = false }
        do {
            if let syncManager = appState.syncManager {
                let tags = try await syncManager.addTag(articleId: articleId, name: trimmed)
                payload?.tags = tags
            } else {
                let tags = try await appState.supabase.addTag(articleId: articleId, name: trimmed)
                payload?.tags = tags
            }
            pendingTagName = ""
        } catch where (error as? SyncManagerError) == .queuedOffline {
            pendingTagName = ""
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeTag(_ tag: CompanionTag) async {
        savingTag = true
        defer { savingTag = false }
        do {
            if let syncManager = appState.syncManager {
                let tags = try await syncManager.removeTag(articleId: articleId, tagId: tag.id)
                payload?.tags = tags
            } else {
                let tags = try await appState.supabase.removeTag(articleId: articleId, tagId: tag.id)
                payload?.tags = tags
            }
        } catch where (error as? SyncManagerError) == .queuedOffline {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptTagSuggestion(_ suggestion: CompanionTagSuggestion) async {
        acceptingSuggestion = suggestion.id
        defer { acceptingSuggestion = nil }
        do {
            if let syncManager = appState.syncManager {
                let tags = try await syncManager.addTag(articleId: articleId, name: suggestion.name)
                payload?.tags = tags
            } else {
                let tags = try await appState.supabase.addTag(articleId: articleId, name: suggestion.name)
                payload?.tags = tags
            }
        } catch where (error as? SyncManagerError) == .queuedOffline {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveReaction(value: Int, reasonCodes: [String]) async {
        if let response = await appState.syncManager?.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes) {
            payload?.reaction = CompanionReaction(
                articleId: response.articleId,
                feedId: nil,
                value: response.value,
                createdAt: nil,
                reasonCodes: response.reasonCodes
            )
        }
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            try await appState.supabase.rerunSummarize(articleId: articleId)
            await loadArticle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Hero Image

// MARK: - Scroll Progress Tracking

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Estimated Reading Time

private func estimatedReadingTime(for article: CompanionArticle) -> Int? {
    let text = article.contentText ?? article.contentHtml?.strippedHTML ?? article.excerpt
    guard let text, !text.isEmpty else { return nil }
    let wordCount = text.split(separator: " ").count
    let minutes = max(1, wordCount / 200) // ~200 WPM average
    return minutes
}

// MARK: - Hero Image

private struct ArticleHeroImage: View {
    let url: URL

    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fill)
            .frame(height: DesignTokens.detailImageHeight)
            .clipped()
    }
}
