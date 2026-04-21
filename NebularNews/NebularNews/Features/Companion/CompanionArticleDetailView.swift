import SwiftUI
import NebularNewsKit

private struct ReactionReasonOption: Identifiable {
    let code: String
    let label: String

    var id: String { code }
}

private let upReactionReasonOptions = [
    ReactionReasonOption(code: "up_interest_match", label: "Matches my interests"),
    ReactionReasonOption(code: "up_source_trust", label: "Trust this source"),
    ReactionReasonOption(code: "up_good_timing", label: "Good timing"),
    ReactionReasonOption(code: "up_good_depth", label: "Good depth"),
    ReactionReasonOption(code: "up_author_like", label: "Like this author")
]

private let downReactionReasonOptions = [
    ReactionReasonOption(code: "down_off_topic", label: "Off topic for me"),
    ReactionReasonOption(code: "down_source_distrust", label: "Don't trust this source"),
    ReactionReasonOption(code: "down_stale", label: "Too old / stale"),
    ReactionReasonOption(code: "down_too_shallow", label: "Too shallow"),
    ReactionReasonOption(code: "down_avoid_author", label: "Avoid this author")
]

// MARK: - Article Detail

struct CompanionArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(AIAssistantCoordinator.self) private var aiAssistant
    @Environment(\.dismiss) private var dismiss

    let articleId: String

    @State private var payload: CompanionArticleDetailPayload?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var pendingTagName = ""
    @State private var savingRead = false
    @State private var savingTag = false
    @State private var savingReaction = false
    @State private var reactionDraft: ReactionDraft?
    @State private var acceptingSuggestion: String?
    @State private var isSaved = false
    @State private var savingBookmark = false
    @State private var showingChat = false
    @State private var showingAddToCollection = false
    @State private var isSummarizing = false
    @State private var isGeneratingKeyPoints = false
    @State private var showingHighlightInput = false
    @State private var highlightText = ""
    @State private var exportedMarkdown: String?
    @State private var isFetchingContent = false

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article…")
            } else if let payload {
                List {
                    if appState.syncManager?.isOffline == true {
                        Section {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .accessibilityHidden(true)
                                Text("Offline — changes will sync later")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                        }
                    }

                    // Hero image — full bleed
                    if let imageUrl = payload.article.imageUrl, let url = URL(string: imageUrl) {
                        Section {
                            CompanionHeroImage(url: url)
                                .listRowInsets(.init())
                        }
                    }

                    // Title + score badge + author
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            if let score = payload.score?.score {
                                ScoreAccentBar(score: score, isRead: payload.article.isReadBool)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(payload.article.title ?? "Untitled article")
                                    .font(.title2.bold())
                                HStack(spacing: 8) {
                                    if let author = payload.article.author, !author.isEmpty {
                                        Text(author)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let score = payload.score?.score {
                                        ScoreBadge(score: score)
                                    }
                                }
                            }
                        }
                    }

                    EnrichmentSection(payload: payload)

                    ArticleBodyView(article: payload.article) {
                        Task { await fetchContent() }
                    }

                    // Highlights
                    if let highlights = payload.highlights, !highlights.isEmpty {
                        HighlightsSection(
                            highlights: highlights,
                            onDelete: { highlight in
                                Task { await deleteHighlight(highlight) }
                            }
                        )
                    }

                    // Annotation
                    AnnotationSection(
                        articleId: articleId,
                        annotation: payload.annotation,
                        onSave: { content in
                            Task { await saveAnnotation(content) }
                        },
                        onDelete: {
                            Task { await deleteAnnotation() }
                        }
                    )

                    // Sources
                    if !payload.sources.isEmpty {
                        Section("Sources") {
                            ForEach(payload.sources) { source in
                                Label(
                                    source.feedTitle ?? source.feedId ?? "Unknown feed",
                                    systemImage: "antenna.radiowaves.left.and.right"
                                )
                                .font(.subheadline)
                            }
                        }
                    }

                    if appState.syncManager?.hasPendingAction(forResource: articleId) == true {
                        Label("Changes will sync when online", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }

                    TagsSection(
                        isEnabled: appState.features?.tags == true,
                        tags: payload.tags,
                        tagSuggestions: payload.tagSuggestions,
                        pendingTagName: $pendingTagName,
                        isSavingTag: savingTag,
                        acceptingSuggestion: acceptingSuggestion,
                        onAddTag: {
                            Task { await addTag() }
                        },
                        onRemoveTag: { tag in
                            Task { await removeTag(tag) }
                        },
                        onAcceptSuggestion: { suggestion in
                            Task { await acceptTagSuggestion(suggestion) }
                        }
                    )

                    // Feedback history
                    if !payload.feedback.isEmpty {
                        Section("Feedback") {
                            ForEach(payload.feedback) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    if let rating = item.rating {
                                        Image(systemName: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                            .foregroundStyle(rating > 0 ? .green : .red)
                                            .font(.caption)
                                            .accessibilityLabel(rating > 0 ? "Thumbs up" : "Thumbs down")
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let comment = item.comment, !comment.isEmpty {
                                            Text(comment).font(.subheadline)
                                        }
                                        if let createdAt = item.createdAt {
                                            Text(Date(timeIntervalSince1970: Double(createdAt)).formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error banner while payload is visible
                    if !errorMessage.isEmpty {
                        Section {
                            ErrorBanner(message: errorMessage) {
                                Task { await loadArticle() }
                            }
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.sidebar)
                #endif
                .navigationTitle("Article")
                .inlineNavigationBarTitle()
                .refreshable { await loadArticle() }
                .hideTabBar()
                .toolbar {
                    ToolbarItemGroup(placement: .platformTrailing) {
                        Button {
                            Task { await toggleReadAndGoBack() }
                        } label: {
                            Image(systemName: payload.article.isReadBool ? "eye.slash" : "eye")
                                .accessibilityLabel(payload.article.isReadBool ? "Mark as unread" : "Mark as read")
                        }
                        .disabled(savingRead)

                        Button {
                            Task { await toggleSaved() }
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .accessibilityLabel(isSaved ? "Remove from saved" : "Save article")
                        }
                        .disabled(savingBookmark)

                        Button {
                            showingAddToCollection = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .accessibilityLabel("Add to collection")
                        }

                        Button {
                            Task { await fetchContent() }
                        } label: {
                            if isFetchingContent {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .accessibilityLabel("Fetch full article")
                            }
                        }
                        .disabled(isFetchingContent)

                        ShareLink(
                            item: MarkdownExporter.exportArticle(
                                article: payload.article,
                                summary: payload.summary,
                                keyPoints: payload.keyPoints,
                                tags: payload.tags,
                                highlights: payload.highlights ?? [],
                                annotation: payload.annotation,
                                sourceName: payload.preferredSource?.feedTitle
                            ),
                            subject: Text(payload.article.title ?? "Article"),
                            message: Text("Exported from NebularNews")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel("Export as Markdown")
                        }
                    }
                    ToolbarItemGroup(placement: .platformBottom) {
                        bottomActionTray(payload)
                    }
                }
                .sheet(item: $reactionDraft) { draft in
                    CompanionReactionReasonSheet(draft: draft) { selectedCodes in
                        Task { await saveReaction(value: draft.value, reasonCodes: selectedCodes) }
                    }
                }
                .sheet(isPresented: $showingChat) {
                    CompanionArticleChatView(
                        articleId: articleId,
                        articleTitle: payload.article.title
                    )
                }
                .sheet(isPresented: $showingAddToCollection) {
                    AddToCollectionSheet(articleId: articleId)
                }
                .alert("Highlight Text", isPresented: $showingHighlightInput) {
                    TextField("Paste selected text", text: $highlightText)
                    Button("Highlight") {
                        Task { await createHighlight() }
                    }
                    Button("Cancel", role: .cancel) {
                        highlightText = ""
                    }
                } message: {
                    Text("Copy text from the article, then paste it here to highlight.")
                }
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "Article unavailable",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(errorMessage.isEmpty ? "Try again later." : errorMessage)
                    )
                    if !errorMessage.isEmpty {
                        Button("Retry") { Task { await loadArticle() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .task {
            if payload == nil {
                await loadArticle()
                pushAssistantContext()
            }
        }
        .onAppear {
            aiAssistant.hideFloatingButton = true
            pushAssistantContext()
        }
        .onDisappear {
            aiAssistant.hideFloatingButton = false
        }
    }

    // MARK: - Bottom action tray

    @ViewBuilder
    private func bottomActionTray(_ payload: CompanionArticleDetailPayload) -> some View {
        if let canonicalURL = payload.article.canonicalUrl, let url = URL(string: canonicalURL) {
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
                let hasSummary = payload.summary?.summaryText?.isEmpty == false
                Label(hasSummary ? "Re-summarize" : "Summarize", systemImage: "sparkles")
            }
        }
        .disabled(isSummarizing)

        Spacer()

        Button {
            Task { await generateKeyPoints() }
        } label: {
            if isGeneratingKeyPoints {
                ProgressView().controlSize(.small)
            } else {
                let hasKeyPoints = payload.keyPoints?.keyPointsJson?.isEmpty == false
                Label(hasKeyPoints ? "Re-extract" : "Key Points", systemImage: "list.bullet.rectangle")
            }
        }
        .disabled(isGeneratingKeyPoints)

        Spacer()

        Button {
            showingChat = true
        } label: {
            Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
        }

        Button {
            showingHighlightInput = true
        } label: {
            Label("Highlight", systemImage: "highlighter")
        }

        ReactionsView(
            isEnabled: appState.features?.reactions == true,
            currentValue: payload.reaction?.value,
            onReact: openReactionDraft
        )
    }

    private func pushAssistantContext() {
        guard let p = payload else { return }
        let keyPoints = p.keyPoints?.keyPointsJson.flatMap { json -> [String]? in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        } ?? nil
        let tags = p.tags.map(\.name)
        let excerpt = String((p.article.contentText ?? "").prefix(500))

        aiAssistant.updateContext(AIPageContext(
            pageType: "article_detail",
            pageLabel: "Article: \(p.article.title ?? "Untitled")",
            articleDetail: AIArticleDetail(
                articleId: p.article.id,
                title: p.article.title ?? "Untitled",
                summary: p.summary?.summaryText,
                keyPoints: keyPoints,
                score: p.score?.score,
                tags: tags,
                contentExcerpt: excerpt
            )
        ))
    }

    private func loadArticle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            payload = try await appState.supabase.fetchArticle(id: articleId)
            errorMessage = ""
            if payload?.article.isRead != 1 {
                await appState.syncManager?.setRead(articleId: articleId, isRead: true)
                payload?.article.isRead = 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleReadAndGoBack() async {
        guard let payload else { return }
        savingRead = true
        let newIsRead = payload.article.isRead != 1
        await appState.syncManager?.setRead(articleId: articleId, isRead: newIsRead)
        dismiss()
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

    private func openReactionDraft(value: Int) {
        let existingCodes = payload?.reaction?.value == value ? (payload?.reaction?.reasonCodes ?? []) : []
        reactionDraft = ReactionDraft(value: value, selectedCodes: existingCodes)
    }

    private func saveReaction(value: Int, reasonCodes: [String]) async {
        savingReaction = true
        defer { savingReaction = false }
        if let response = await appState.syncManager?.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes) {
            payload?.reaction = CompanionReaction(
                articleId: response.articleId,
                feedId: nil,
                value: response.value,
                createdAt: response.createdAt.flatMap { timestampMillisFromISO($0) },
                reasonCodes: response.reasonCodes
            )
            reactionDraft = nil
        } else {
            // Fallback: direct Supabase call if syncManager not available
            do {
                let response = try await appState.supabase.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes)
                payload?.reaction = CompanionReaction(
                    articleId: response.articleId,
                    feedId: nil,
                    value: response.value,
                    createdAt: response.createdAt.flatMap { timestampMillisFromISO($0) },
                    reasonCodes: response.reasonCodes
                )
                reactionDraft = nil
            } catch {
                errorMessage = error.localizedDescription
            }
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

    private func generateKeyPoints() async {
        isGeneratingKeyPoints = true
        defer { isGeneratingKeyPoints = false }
        do {
            try await appState.supabase.generateKeyPoints(articleId: articleId)
            await loadArticle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSaved() async {
        savingBookmark = true
        defer { savingBookmark = false }
        if let response = await appState.syncManager?.saveArticle(articleId: articleId, saved: !isSaved) {
            isSaved = response.saved
        } else {
            // Fallback: direct Supabase call if syncManager not available
            do {
                let response = try await appState.supabase.saveArticle(id: articleId, saved: !isSaved)
                isSaved = response.saved
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Full-content fetch

    private func fetchContent() async {
        isFetchingContent = true
        defer { isFetchingContent = false }
        do {
            let result = try await appState.supabase.fetchFullContent(articleId: articleId)
            payload?.article.contentHtml = result.contentHtml
            payload?.article.contentText = result.contentText
            payload?.article.excerpt = result.excerpt
            payload?.article.wordCount = result.wordCount
            payload?.article.lastFetchAttemptAt = result.lastFetchAttemptAt
            payload?.article.lastFetchError = result.lastFetchError
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Highlights

    private func createHighlight() async {
        let text = highlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let highlight = try await appState.supabase.createHighlight(articleId: articleId, selectedText: text)
            if payload?.highlights != nil {
                payload?.highlights?.append(highlight)
            } else {
                payload?.highlights = [highlight]
            }
            highlightText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteHighlight(_ highlight: CompanionHighlight) async {
        do {
            try await appState.supabase.deleteHighlight(articleId: articleId, highlightId: highlight.id)
            payload?.highlights?.removeAll { $0.id == highlight.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Annotations

    private func saveAnnotation(_ content: String) async {
        do {
            let annotation = try await appState.supabase.upsertAnnotation(articleId: articleId, content: content)
            payload?.annotation = annotation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAnnotation() async {
        do {
            try await appState.supabase.deleteAnnotation(articleId: articleId)
            payload?.annotation = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Parse an ISO 8601 timestamp string into milliseconds since epoch.
private func timestampMillisFromISO(_ isoString: String) -> Int? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: isoString) {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    return nil
}

private struct EnrichmentSection: View {
    let payload: CompanionArticleDetailPayload

    private var keyPoints: [String] {
        guard let jsonString = payload.keyPoints?.keyPointsJson,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let points = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return points
    }

    private var evidenceItems: [ScoreEvidenceItem] {
        guard let evidenceJson = payload.score?.evidenceJson,
              !evidenceJson.isEmpty,
              let data = evidenceJson.data(using: .utf8),
              let items = try? JSONDecoder().decode([ScoreEvidenceItem].self, from: data) else {
            return []
        }
        return items
    }

    @ViewBuilder
    var body: some View {
        if let summary = payload.summary?.summaryText, !summary.isEmpty {
            Section("Summary") {
                Text(summary)
                    .font(.body)
                    .lineSpacing(3)
            }
        }

        if !keyPoints.isEmpty {
            Section("Key Points") {
                ForEach(keyPoints, id: \.self) { point in
                    Label(point, systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .imageScale(.small)
                }
            }
        }

        if let score = payload.score, let scoreValue = score.score {
            Section("Fit Score") {
                DisclosureGroup {
                    if let reasonText = score.reasonText, !reasonText.isEmpty {
                        Text(reasonText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(evidenceItems) { item in
                        Label {
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: item.weight > 0 ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(item.weight > 0 ? .green : .red)
                                .accessibilityLabel(item.weight > 0 ? "Positive signal" : "Negative signal")
                        }
                        .font(.caption)
                    }
                } label: {
                    HStack {
                        Text("Score: \(scoreValue)/5")
                            .font(.headline)
                        if let label = score.label, !label.isEmpty {
                            Text(label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let confidence = score.confidence {
                            Text("\(Int(confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct ArticleBodyView: View {
    let article: CompanionArticle
    var onFetchRequested: (() -> Void)? = nil

    private let readableMaxWidth: CGFloat = 720

    @ViewBuilder
    var body: some View {
        if let contentHtml = article.contentHtml, !contentHtml.isEmpty {
            Section {
                RichArticleContentView(html: contentHtml, onFetchRequested: onFetchRequested)
                    .frame(maxWidth: readableMaxWidth, alignment: .leading)
            }
        } else if let contentText = article.contentText, !contentText.isEmpty {
            Section {
                Text(contentText)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: readableMaxWidth, alignment: .leading)
            }
        } else if let excerpt = article.excerpt, !excerpt.isEmpty {
            Section("Excerpt") {
                Text(excerpt)
                    .frame(maxWidth: readableMaxWidth, alignment: .leading)
            }
        } else if let onFetch = onFetchRequested {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Only a title and link came in from the feed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        onFetch()
                    } label: {
                        Label("Fetch Full Article", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: readableMaxWidth, alignment: .leading)
            }
        }
    }
}

private struct TagsSection: View {
    let isEnabled: Bool
    let tags: [CompanionTag]
    let tagSuggestions: [CompanionTagSuggestion]
    @Binding var pendingTagName: String
    let isSavingTag: Bool
    let acceptingSuggestion: String?
    let onAddTag: () -> Void
    let onRemoveTag: (CompanionTag) -> Void
    let onAcceptSuggestion: (CompanionTagSuggestion) -> Void

    @ViewBuilder
    var body: some View {
        if isEnabled {
            Section("Tags") {
                if tags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            HStack(spacing: 4) {
                                TagPill(name: tag.name)
                                Button {
                                    onRemoveTag(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Remove tag \(tag.name)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Add tag", text: $pendingTagName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        onAddTag()
                    }
                    .disabled(pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingTag)
                }
            }
        }

        if !tagSuggestions.isEmpty {
            Section("Suggested Tags") {
                ForEach(tagSuggestions) { suggestion in
                    HStack {
                        TagPill(name: suggestion.name)
                        if let confidence = suggestion.confidence {
                            Text("\(Int(confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Accept") {
                            onAcceptSuggestion(suggestion)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(acceptingSuggestion == suggestion.id)
                    }
                }
            }
        }
    }
}

private struct ReactionsView: View {
    let isEnabled: Bool
    let currentValue: Int?
    let onReact: (Int) -> Void

    @ViewBuilder
    var body: some View {
        if isEnabled {
            Spacer()

            Button {
                onReact(1)
            } label: {
                Image(systemName: currentValue == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .accessibilityLabel("Like article")
            }

            Button {
                onReact(-1)
            } label: {
                Image(systemName: currentValue == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .accessibilityLabel("Dislike article")
            }
        }
    }
}

// MARK: - Companion Hero Image

private struct CompanionHeroImage: View {
    let url: URL

    private let baseHeight = DesignTokens.companionDetailImageHeight

    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fill)
            .frame(height: baseHeight)
        .clipped()
    }
}

private struct ScoreEvidenceItem: Decodable, Identifiable {
    let reason: String
    let weight: Double

    var id: String { reason }
}

// MARK: - Reaction Sheet

private struct ReactionDraft: Identifiable {
    let value: Int
    var selectedCodes: [String]

    var id: Int { value }
}

private struct CompanionReactionReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: ReactionDraft
    let onSave: ([String]) -> Void

    @State private var selectedCodes: Set<String>

    init(draft: ReactionDraft, onSave: @escaping ([String]) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _selectedCodes = State(initialValue: Set(draft.selectedCodes))
    }

    private var options: [ReactionReasonOption] {
        draft.value == 1 ? upReactionReasonOptions : downReactionReasonOptions
    }

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    if selectedCodes.contains(option.code) {
                        selectedCodes.remove(option.code)
                    } else {
                        selectedCodes.insert(option.code)
                    }
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if selectedCodes.contains(option.code) {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(draft.value == 1 ? "Why did you like this?" : "Why didn't this work?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(options.filter { selectedCodes.contains($0.code) }.map(\.code))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .platformBottom) {
                    Button("Skip") {
                        onSave([])
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Highlights Section

private struct HighlightsSection: View {
    let highlights: [CompanionHighlight]
    let onDelete: (CompanionHighlight) -> Void

    var body: some View {
        Section {
            ForEach(highlights) { highlight in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(highlightColor(highlight.color))
                            .frame(width: 3)

                        Text(highlight.selectedText)
                            .font(.subheadline)
                            .italic()
                    }

                    if let note = highlight.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 11)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onDelete(highlight)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Label("Highlights", systemImage: "highlighter")
        }
    }

    private func highlightColor(_ name: String?) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "pink": return .pink
        case "orange": return .orange
        default: return .yellow
        }
    }
}

// MARK: - Annotation Section

private struct AnnotationSection: View {
    let articleId: String
    let annotation: CompanionAnnotation?
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        Section {
            if let annotation {
                VStack(alignment: .leading, spacing: 8) {
                    Text(annotation.content)
                        .font(.subheadline)

                    HStack {
                        Button("Edit") {
                            editText = annotation.content
                            isEditing = true
                        }
                        .font(.caption)

                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                        .font(.caption)
                    }
                }
            } else {
                Button {
                    editText = ""
                    isEditing = true
                } label: {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                }
            }
        } header: {
            Label("Notes", systemImage: "note.text")
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                TextEditor(text: $editText)
                    .padding()
                    .navigationTitle("Note")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isEditing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    onSave(text)
                                }
                                isEditing = false
                            }
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
        }
    }
}
