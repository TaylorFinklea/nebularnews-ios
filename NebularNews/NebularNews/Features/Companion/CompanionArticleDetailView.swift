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
    @State private var isSummarizing = false
    @State private var isGeneratingKeyPoints = false

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
                                ScoreAccentBar(score: score, isRead: payload.article.isRead == 1)
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

                    // Summary
                    if let summary = payload.summary?.summaryText, !summary.isEmpty {
                        Section("Summary") {
                            Text(summary)
                                .font(.body)
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
                        Section("Key Points") {
                            ForEach(points, id: \.self) { point in
                                Label(point, systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline)
                                    .imageScale(.small)
                            }
                        }
                    }

                    // Article body
                    if let contentHtml = payload.article.contentHtml, !contentHtml.isEmpty {
                        Section {
                            RichArticleContentView(html: contentHtml)
                        }
                    } else if let contentText = payload.article.contentText, !contentText.isEmpty {
                        Section {
                            Text(contentText)
                                .font(.body)
                                .lineSpacing(4)
                        }
                    } else if let excerpt = payload.article.excerpt, !excerpt.isEmpty {
                        Section("Excerpt") {
                            Text(excerpt)
                        }
                    }

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

                    // Fit score with DisclosureGroup for evidence
                    if let score = payload.score, let scoreValue = score.score {
                        Section("Fit Score") {
                            DisclosureGroup {
                                if let reasonText = score.reasonText, !reasonText.isEmpty {
                                    Text(reasonText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let evidenceJson = score.evidenceJson,
                                   !evidenceJson.isEmpty,
                                   let data = evidenceJson.data(using: .utf8),
                                   let items = try? JSONDecoder().decode([ScoreEvidenceItem].self, from: data) {
                                    ForEach(items) { item in
                                        Label {
                                            Text(item.reason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } icon: {
                                            Image(systemName: item.weight > 0 ? "plus.circle.fill" : "minus.circle.fill")
                                                .foregroundStyle(item.weight > 0 ? .green : .red)
                                        }
                                        .font(.caption)
                                    }
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

                    // Tags
                    if appState.features?.tags == true {
                        Section("Tags") {
                            if payload.tags.isEmpty {
                                Text("No tags yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(payload.tags) { tag in
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
                            HStack {
                                TextField("Add tag", text: $pendingTagName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Add") {
                                    Task { await addTag() }
                                }
                                .disabled(pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingTag)
                            }
                        }
                    }

                    // Tag suggestions
                    if !payload.tagSuggestions.isEmpty {
                        Section("Suggested Tags") {
                            ForEach(payload.tagSuggestions) { suggestion in
                                HStack {
                                    TagPill(name: suggestion.name)
                                    if let confidence = suggestion.confidence {
                                        Text("\(Int(confidence * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Accept") {
                                        Task { await acceptTagSuggestion(suggestion) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(acceptingSuggestion == suggestion.id)
                                }
                            }
                        }
                    }

                    // Feedback history
                    if !payload.feedback.isEmpty {
                        Section("Feedback") {
                            ForEach(payload.feedback) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    if let rating = item.rating {
                                        Image(systemName: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                            .foregroundStyle(rating > 0 ? .green : .red)
                                            .font(.caption)
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
                .listStyle(.insetGrouped)
                .navigationTitle("Article")
                .inlineNavigationBarTitle()
                .refreshable { await loadArticle() }
                .hideTabBar()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await toggleReadAndGoBack() }
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
                    ToolbarItemGroup(placement: .bottomBar) {
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
            }
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

        if appState.features?.reactions == true {
            Spacer()

            Button {
                openReactionDraft(value: 1)
            } label: {
                Image(systemName: payload.reaction?.value == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
            }

            Button {
                openReactionDraft(value: -1)
            } label: {
                Image(systemName: payload.reaction?.value == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
        }
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

// MARK: - Companion Hero Image

private struct CompanionHeroImage: View {
    let url: URL

    private let baseHeight: CGFloat = 280

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color.platformTertiaryFill)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            case .empty:
                Rectangle()
                    .fill(Color.platformTertiaryFill)
                    .overlay { ProgressView() }
            @unknown default:
                EmptyView()
            }
        }
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
                ToolbarItem(placement: .bottomBar) {
                    Button("Skip") {
                        onSave([])
                        dismiss()
                    }
                }
            }
        }
    }
}
