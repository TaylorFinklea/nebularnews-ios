import SwiftUI
import UIKit
import UniformTypeIdentifiers
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

// MARK: - Error Banner

private struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Dashboard

struct CompanionDashboardView: View {
    @Environment(AppState.self) private var appState

    @State private var dashboard: CompanionDashboardPayload?
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && dashboard == nil {
                    ProgressView("Loading dashboard…")
                } else if let dashboard {
                    List {
                        if !errorMessage.isEmpty {
                            Section {
                                ErrorBanner(message: errorMessage) {
                                    Task { await loadDashboard() }
                                }
                                .listRowInsets(.init())
                                .listRowBackground(Color.clear)
                            }
                        }

                        if appState.features?.newsBrief == true, let newsBrief = dashboard.newsBrief {
                            Section(newsBrief.title) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(newsBrief.editionLabel)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Last \(newsBrief.windowHours) hours · \(newsBrief.scoreCutoff)/5 and up")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if newsBrief.stale {
                                        Text("Stale")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                if newsBrief.bullets.isEmpty {
                                    Text("No qualifying developments yet.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(newsBrief.bullets) { bullet in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("• \(bullet.text)")
                                            ForEach(bullet.sources) { source in
                                                NavigationLink(destination: CompanionArticleDetailView(articleId: source.articleId)) {
                                                    Text(source.title)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        Section("Reading momentum") {
                            MetricRow(label: "Unread total", value: dashboard.momentum.unreadTotal)
                            MetricRow(label: "Unread · 24h", value: dashboard.momentum.unread24h)
                            MetricRow(label: "Unread · 7d", value: dashboard.momentum.unread7d)
                            MetricRow(label: "High fit · 7d", value: dashboard.momentum.highFitUnread7d)
                        }

                        Section("Top unread") {
                            if dashboard.readingQueue.isEmpty {
                                Text("No unread queue items yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(dashboard.readingQueue) { article in
                                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                                        ArticleRow(article: article)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        _ = try? await appState.mobileAPI.triggerPull()
                        try? await Task.sleep(for: .seconds(2))
                        await loadDashboard()
                    }
                } else {
                    VStack(spacing: 20) {
                        if !errorMessage.isEmpty {
                            ContentUnavailableView("Dashboard unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                            Button("Retry") { Task { await loadDashboard() } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            ContentUnavailableView("No dashboard data", systemImage: "house")
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .task {
                if dashboard == nil {
                    await loadDashboard()
                }
            }
        }
    }

    private func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await appState.mobileAPI.fetchDashboard()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Companion Filter Bar

private struct CompanionFilterBar: View {
    @Binding var filter: CompanionArticleFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Status", selection: $filter.readFilter) {
                ForEach(CompanionReadFilter.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            HStack(spacing: 12) {
                Menu {
                    ForEach(CompanionSortOrder.allCases, id: \.self) { order in
                        Button {
                            filter.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.label)
                                if filter.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(filter.sortOrder.label, systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }

                Menu {
                    Button {
                        filter.minScore = nil
                    } label: {
                        HStack {
                            Text("Any score")
                            if filter.minScore == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach([3, 4, 5], id: \.self) { threshold in
                        Button {
                            filter.minScore = threshold
                        } label: {
                            HStack {
                                Text("\(threshold)+ score")
                                if filter.minScore == threshold { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Label(filter.minScore.map { "\($0)+" } ?? "Score", systemImage: "star")
                        .font(.caption)
                }

                Spacer()

                if filter.isActive {
                    Button("Clear") {
                        withAnimation { filter.reset() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

// MARK: - Articles

struct CompanionArticlesView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var filter = CompanionArticleFilter()
    @State private var recentSearches: [String] = {
        UserDefaults.standard.stringArray(forKey: "companionRecentSearches") ?? []
    }()

    private var hasMore: Bool { articles.count < total }

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty && articles.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage) {
                            Task { await loadArticles() }
                        }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    CompanionFilterBar(filter: $filter)
                        .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(articles) { article in
                        NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                            ArticleRow(article: article)
                        }
                    }

                    if hasMore {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await loadMoreArticles() }
                                    }
                            }
                            Spacer()
                        }
                    }
                }

                if !errorMessage.isEmpty && !articles.isEmpty {
                    Section {
                        ErrorBanner(message: errorMessage) {
                            Task { await loadMoreArticles() }
                        }
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .overlay {
                if isLoading && articles.isEmpty {
                    ProgressView("Loading articles…")
                }
            }
            .navigationTitle("Articles")
            .searchable(text: $query, prompt: "Search articles")
            .searchSuggestions {
                if query.isEmpty && !recentSearches.isEmpty {
                    ForEach(recentSearches, id: \.self) { recent in
                        Text(recent)
                            .searchCompletion(recent)
                    }
                }
            }
            .onSubmit(of: .search) {
                saveRecentSearch(query)
            }
            .task(id: FilterKey(query: query, filter: filter)) {
                await loadArticles()
            }
            .refreshable {
                _ = try? await appState.mobileAPI.triggerPull()
                try? await Task.sleep(for: .seconds(2))
                await loadArticles()
            }
        }
    }

    private func loadArticles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(
                query: query,
                offset: 0,
                read: filter.readFilter,
                minScore: filter.minScore,
                sort: filter.sortOrder
            )
            articles = payload.articles
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreArticles() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(
                query: query,
                offset: articles.count,
                read: filter.readFilter,
                minScore: filter.minScore,
                sort: filter.sortOrder
            )
            articles.append(contentsOf: payload.articles)
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        UserDefaults.standard.set(recentSearches, forKey: "companionRecentSearches")
    }
}

private struct FilterKey: Equatable {
    let query: String
    let filter: CompanionArticleFilter
}


// MARK: - Article Detail (Immersive Reader)

struct CompanionArticleDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var scoreExpanded = false
    @State private var isSaved = false
    @State private var savingBookmark = false

    private var palette: NebularPalette { NebularPalette.forColorScheme(colorScheme) }

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article…")
            } else if let payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hero image
                        if let imageUrl = payload.article.imageUrl, let url = URL(string: imageUrl) {
                            CompanionHeroImage(url: url)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            // Score accent + title
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

                            // Source attribution
                            if !payload.sources.isEmpty {
                                GlassCard(style: .compact) {
                                    ForEach(payload.sources) { source in
                                        HStack(spacing: 8) {
                                            Image(systemName: "antenna.radiowaves.left.and.right")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                            Text(source.feedTitle ?? source.feedId ?? "Unknown feed")
                                                .font(.subheadline.weight(.medium))
                                        }
                                    }
                                }
                            }

                            // Score evidence disclosure
                            if let score = payload.score, let scoreValue = score.score {
                                GlassCard(style: .standard, tintColor: Color.forScore(scoreValue)) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Fit score: \(scoreValue)/5")
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
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    scoreExpanded.toggle()
                                                }
                                            } label: {
                                                Image(systemName: scoreExpanded ? "chevron.up" : "chevron.down")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.borderless)
                                        }

                                        if scoreExpanded {
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
                                                    HStack(alignment: .top, spacing: 6) {
                                                        Image(systemName: item.weight > 0 ? "plus.circle.fill" : "minus.circle.fill")
                                                            .foregroundStyle(item.weight > 0 ? .green : .red)
                                                            .font(.caption)
                                                        Text(item.reason)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Summary
                            if let summary = payload.summary?.summaryText, !summary.isEmpty {
                                GlassCard(style: .standard) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Summary").font(.headline)
                                        Text(summary)
                                    }
                                }
                            }

                            // Key points
                            if let keyPoints = payload.keyPoints,
                               let jsonString = keyPoints.keyPointsJson,
                               !jsonString.isEmpty,
                               let data = jsonString.data(using: .utf8),
                               let points = try? JSONDecoder().decode([String].self, from: data),
                               !points.isEmpty {
                                GlassCard(style: .standard) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Key points").font(.headline)
                                        ForEach(points, id: \.self) { point in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•").foregroundStyle(.secondary)
                                                Text(point)
                                            }
                                        }
                                    }
                                }
                            }

                            // Rich article content
                            if let contentHtml = payload.article.contentHtml, !contentHtml.isEmpty {
                                GlassCard(style: .raised) {
                                    RichArticleContentView(html: contentHtml)
                                }
                            } else if let contentText = payload.article.contentText, !contentText.isEmpty {
                                GlassCard(style: .raised) {
                                    Text(contentText)
                                        .font(.body)
                                        .lineSpacing(4)
                                }
                            } else if let excerpt = payload.article.excerpt, !excerpt.isEmpty {
                                GlassCard(style: .standard) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Excerpt").font(.headline)
                                        Text(excerpt)
                                    }
                                }
                            }

                            // Tag suggestions
                            if !payload.tagSuggestions.isEmpty {
                                GlassCard(style: .compact) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Suggested tags").font(.headline)
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
                            }

                            // Feedback history
                            if !payload.feedback.isEmpty {
                                GlassCard(style: .compact) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Feedback history").font(.headline)
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
                            }

                            // Tags
                            if appState.features?.tags == true {
                                GlassCard(style: .compact) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Tags").font(.headline)
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
                            }

                            // Error banner while payload is visible
                            if !errorMessage.isEmpty {
                                ErrorBanner(message: errorMessage) {
                                    Task { await loadArticle() }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .background(NebularBackdrop())
                .navigationTitle("Article")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await loadArticle() }
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        bottomActionTray(payload)
                    }
                }
                .sheet(item: $reactionDraft) { draft in
                    CompanionReactionReasonSheet(draft: draft) { selectedCodes in
                        Task { await saveReaction(value: draft.value, reasonCodes: selectedCodes) }
                    }
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
            Task { await toggleSaved() }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
        }
        .disabled(savingBookmark)

        Spacer()

        Button(payload.article.isRead == 1 ? "Mark unread" : "Mark read") {
            Task { await toggleRead() }
        }
        .disabled(savingRead)

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
            payload = try await appState.mobileAPI.fetchArticle(id: articleId)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRead() async {
        guard let payload else { return }
        savingRead = true
        defer { savingRead = false }
        do {
            try await appState.mobileAPI.setRead(articleId: articleId, isRead: payload.article.isRead != 1)
            await loadArticle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addTag() async {
        let trimmed = pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savingTag = true
        defer { savingTag = false }
        do {
            let tags = try await appState.mobileAPI.addTag(articleId: articleId, name: trimmed)
            payload?.tags = tags
            pendingTagName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeTag(_ tag: CompanionTag) async {
        savingTag = true
        defer { savingTag = false }
        do {
            let tags = try await appState.mobileAPI.removeTag(articleId: articleId, tagId: tag.id)
            payload?.tags = tags
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptTagSuggestion(_ suggestion: CompanionTagSuggestion) async {
        acceptingSuggestion = suggestion.id
        defer { acceptingSuggestion = nil }
        do {
            let tags = try await appState.mobileAPI.addTag(articleId: articleId, name: suggestion.name)
            payload?.tags = tags
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
        do {
            let reaction = try await appState.mobileAPI.setReaction(articleId: articleId, value: value, reasonCodes: reasonCodes)
            payload?.reaction = reaction
            reactionDraft = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSaved() async {
        savingBookmark = true
        defer { savingBookmark = false }
        do {
            let response = try await appState.mobileAPI.saveArticle(id: articleId, saved: !isSaved)
            isSaved = response.saved
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Companion Hero Image

private struct CompanionHeroImage: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    private let baseHeight: CGFloat = 280

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(palette.surfaceSoft)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            case .empty:
                Rectangle()
                    .fill(palette.surfaceSoft)
                    .overlay { ProgressView() }
            @unknown default:
                EmptyView()
            }
        }
        .frame(height: baseHeight)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, palette.heroGradientEnd.opacity(0.6), palette.heroGradientEnd],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
    }
}

// MARK: - Feeds

struct CompanionFeedsView: View {
    @Environment(AppState.self) private var appState

    @State private var feeds: [CompanionFeed] = []
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingAddFeed = false
    @State private var showingImport = false
    @State private var deletingFeed: CompanionFeed?

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage) {
                    Task { await loadFeeds() }
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            ForEach(feeds) { feed in
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title?.isEmpty == false ? feed.title! : feed.url)
                        .font(.headline)
                    Text(feed.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let articleCount = feed.articleCount {
                            Text("\(articleCount) article\(articleCount == 1 ? "" : "s")")
                        }
                        if let errorCount = feed.errorCount, errorCount > 0 {
                            Label("\(errorCount) error\(errorCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if feed.disabled == 1 {
                            Text("Disabled")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deletingFeed = feed
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await exportOPML() }
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if isLoading && feeds.isEmpty {
                ProgressView("Loading feeds…")
            }
        }
        .task {
            if feeds.isEmpty {
                await loadFeeds()
            }
        }
        .refreshable { await loadFeeds() }
        .sheet(isPresented: $showingAddFeed) {
            CompanionAddFeedSheet { url in
                Task {
                    do {
                        _ = try await appState.mobileAPI.addFeed(url: url)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            CompanionOPMLImportSheet { xml in
                Task {
                    do {
                        _ = try await appState.mobileAPI.importOPML(xml: xml)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert(
            "Delete Feed",
            isPresented: Binding(
                get: { deletingFeed != nil },
                set: { if !$0 { deletingFeed = nil } }
            ),
            presenting: deletingFeed
        ) { feed in
            Button("Delete", role: .destructive) {
                Task { await deleteFeed(feed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { feed in
            Text("Delete \"\(feed.title ?? feed.url)\" and all its exclusive articles?")
        }
    }

    private func loadFeeds() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await appState.mobileAPI.fetchFeeds()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFeed(_ feed: CompanionFeed) async {
        do {
            _ = try await appState.mobileAPI.deleteFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportOPML() async {
        do {
            let xml = try await appState.mobileAPI.exportOPML()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("nebular-news.opml")
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else { return }
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Feed Sheet

private struct CompanionAddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String) -> Void
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - OPML Import Sheet

private struct CompanionOPMLImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (String) -> Void
    @State private var showingFilePicker = false
    @State private var importedXML: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select an OPML file to import feeds.")
                    .foregroundStyle(.secondary)
                Button("Choose File") {
                    showingFilePicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Import OPML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.xml, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let xml = try? String(contentsOf: url, encoding: .utf8) {
                    onImport(xml)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Settings

struct CompanionSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Mode", value: "Companion")
                LabeledContent("Server", value: appState.companionServerURL?.absoluteString ?? "Not connected")
                Button("Disconnect server", role: .destructive) {
                    appState.disconnectCompanion()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - More

struct CompanionMoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: CompanionDashboardView()) {
                    Label("Dashboard", systemImage: "house")
                }
                NavigationLink(destination: CompanionFeedsView()) {
                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                }
                NavigationLink(destination: CompanionSettingsView()) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Shared subviews

private struct MetricRow: View {
    let label: String
    let value: Int?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.map(String.init) ?? "—")
                .fontWeight(.semibold)
        }
    }
}

private struct ArticleRow: View {
    let article: CompanionArticleListItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoreAccentBar(score: article.score, isRead: article.isRead == 1, width: 3)
                .frame(height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "Untitled article")
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let sourceName = article.sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                    }
                    if let score = article.score {
                        ScoreBadge(score: score)
                    }
                    if article.isRead == 1 {
                        Text("Read")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(NebularPalette.forColorScheme(colorScheme).surfaceSoft)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ScoreEvidenceItem: Decodable, Identifiable {
    let reason: String
    let weight: Double

    var id: String { reason }
}

// MARK: - Flow Layout (for tag pills)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
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
