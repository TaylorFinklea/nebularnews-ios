import SwiftUI

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
                    .refreshable { await loadDashboard() }
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

// MARK: - Articles

struct CompanionArticlesView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false

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
            .task(id: query) {
                await loadArticles()
            }
            .refreshable { await loadArticles() }
        }
    }

    private func loadArticles() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.mobileAPI.fetchArticles(query: query, offset: 0)
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
            let payload = try await appState.mobileAPI.fetchArticles(query: query, offset: articles.count)
            articles.append(contentsOf: payload.articles)
            total = payload.total
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Article Detail

struct CompanionArticleDetailView: View {
    @Environment(AppState.self) private var appState

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

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article…")
            } else if let payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title + meta
                        VStack(alignment: .leading, spacing: 8) {
                            Text(payload.article.title ?? "Untitled article")
                                .font(.title.bold())
                            if let author = payload.article.author, !author.isEmpty {
                                Text(author)
                                    .foregroundStyle(.secondary)
                            }
                            if let canonicalURL = payload.article.canonicalUrl,
                               let url = URL(string: canonicalURL) {
                                Link(destination: url) {
                                    Label("Open article", systemImage: "arrow.up.right.square")
                                }
                            }
                        }

                        // Source attribution
                        if !payload.sources.isEmpty {
                            SectionCard(title: "Source") {
                                ForEach(payload.sources) { source in
                                    HStack(spacing: 8) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.feedTitle ?? source.feedId ?? "Unknown feed")
                                                .font(.subheadline.weight(.medium))
                                            if let siteUrl = source.siteUrl {
                                                Text(siteUrl)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Score with expandable evidence
                        if let score = payload.score, let scoreValue = score.score {
                            SectionCard(title: "Fit score") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("\(scoreValue)/5")
                                            .font(.title2.weight(.semibold))
                                        if let label = score.label, !label.isEmpty {
                                            Text(label)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let confidence = score.confidence {
                                            Text("\(Int(confidence * 100))% confident")
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

                        // Summary or excerpt
                        if let summary = payload.summary?.summaryText, !summary.isEmpty {
                            SectionCard(title: "Summary") {
                                Text(summary)
                            }
                        } else if let excerpt = payload.article.excerpt, !excerpt.isEmpty {
                            SectionCard(title: "Excerpt") {
                                Text(excerpt)
                            }
                        }

                        // Key points
                        if let keyPoints = payload.keyPoints,
                           let jsonString = keyPoints.keyPointsJson,
                           !jsonString.isEmpty,
                           let data = jsonString.data(using: .utf8),
                           let points = try? JSONDecoder().decode([String].self, from: data),
                           !points.isEmpty {
                            SectionCard(title: "Key points") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(points, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundStyle(.secondary)
                                            Text(point)
                                        }
                                    }
                                }
                            }
                        }

                        // Tag suggestions
                        if !payload.tagSuggestions.isEmpty {
                            SectionCard(title: "Suggested tags") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(payload.tagSuggestions) { suggestion in
                                        HStack {
                                            Image(systemName: "tag")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(suggestion.name)
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

                        // Actions
                        SectionCard(title: "Actions") {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(payload.article.isRead == 1 ? "Mark unread" : "Mark read") {
                                    Task { await toggleRead() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(savingRead)

                                if appState.features?.reactions == true {
                                    HStack {
                                        Button("Thumbs up") {
                                            openReactionDraft(value: 1)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Thumbs down") {
                                            openReactionDraft(value: -1)
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    if let reaction = payload.reaction {
                                        Text("Current reaction: \(reaction.value == 1 ? "Thumbs up" : "Thumbs down")")
                                            .font(.subheadline)
                                        if let reasonCodes = reaction.reasonCodes, !reasonCodes.isEmpty {
                                            Text(reasonCodes.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        // Tags
                        if appState.features?.tags == true {
                            SectionCard(title: "Tags") {
                                VStack(alignment: .leading, spacing: 12) {
                                    if payload.tags.isEmpty {
                                        Text("No tags yet.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(payload.tags) { tag in
                                            HStack {
                                                Text(tag.name)
                                                Spacer()
                                                Button(role: .destructive) {
                                                    Task { await removeTag(tag) }
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.borderless)
                                            }
                                        }
                                    }

                                    HStack {
                                        TextField("Add manual tag", text: $pendingTagName)
                                            .textFieldStyle(.roundedBorder)
                                        Button("Add") {
                                            Task { await addTag() }
                                        }
                                        .disabled(pendingTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingTag)
                                    }
                                }
                            }
                        }

                        // Full text
                        if let content = payload.article.contentText, !content.isEmpty {
                            SectionCard(title: "Full text") {
                                Text(content)
                                    .font(.body)
                            }
                        }

                        // Feedback history
                        if !payload.feedback.isEmpty {
                            SectionCard(title: "Feedback history") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(payload.feedback) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            if let rating = item.rating {
                                                Image(systemName: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                                    .foregroundStyle(rating > 0 ? .green : .red)
                                                    .font(.caption)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                if let comment = item.comment, !comment.isEmpty {
                                                    Text(comment)
                                                        .font(.subheadline)
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

                        // Error banner while payload is visible
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage) {
                                Task { await loadArticle() }
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Article")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable { await loadArticle() }
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
}

// MARK: - Feeds

struct CompanionFeedsView: View {
    @Environment(AppState.self) private var appState

    @State private var feeds: [CompanionFeed] = []
    @State private var errorMessage = ""
    @State private var isLoading = false

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
            }
        }
        .navigationTitle("Feeds")
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

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "Untitled article")
                .font(.headline)
            HStack(spacing: 8) {
                if let sourceName = article.sourceName, !sourceName.isEmpty {
                    Text(sourceName)
                }
                if let score = article.score {
                    Text("\(score)/5")
                }
                if article.isRead == 1 {
                    Text("Read")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ScoreEvidenceItem: Decodable, Identifiable {
    let reason: String
    let weight: Double

    var id: String { reason }
}

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
