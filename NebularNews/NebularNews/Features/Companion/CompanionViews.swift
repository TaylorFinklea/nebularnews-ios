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
                        if let newsBrief = dashboard.newsBrief {
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
                } else if !errorMessage.isEmpty {
                    ContentUnavailableView("Dashboard unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else {
                    ContentUnavailableView("No dashboard data", systemImage: "house")
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

struct CompanionArticlesView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var articles: [CompanionArticleListItem] = []
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(articles) { article in
                        NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                            ArticleRow(article: article)
                        }
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
            let payload = try await appState.mobileAPI.fetchArticles(query: query)
            articles = payload.articles
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article…")
            } else if let payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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

                        if let score = payload.score?.score {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fit score")
                                    .font(.headline)
                                Text("\(score)/5")
                                    .font(.title2.weight(.semibold))
                                if let label = payload.score?.label, !label.isEmpty {
                                    Text(label)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let summary = payload.summary?.summaryText, !summary.isEmpty {
                            SectionCard(title: "Summary") {
                                Text(summary)
                            }
                        } else if let excerpt = payload.article.excerpt, !excerpt.isEmpty {
                            SectionCard(title: "Excerpt") {
                                Text(excerpt)
                            }
                        }

                        SectionCard(title: "Actions") {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(payload.article.isRead == 1 ? "Mark unread" : "Mark read") {
                                    Task { await toggleRead() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(savingRead)

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

                        if let content = payload.article.contentText, !content.isEmpty {
                            SectionCard(title: "Full text") {
                                Text(content)
                                    .font(.body)
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
                ContentUnavailableView("Article unavailable", systemImage: "doc.text.magnifyingglass", description: Text(errorMessage.isEmpty ? "Try again later." : errorMessage))
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

struct CompanionFeedsView: View {
    @Environment(AppState.self) private var appState

    @State private var feeds: [CompanionFeed] = []
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            ForEach(feeds) { feed in
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title?.isEmpty == false ? feed.title! : feed.url)
                        .font(.headline)
                    Text(feed.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let articleCount = feed.articleCount {
                        Text("\(articleCount) article\(articleCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            .navigationTitle(draft.value == 1 ? "Why did you like this?" : "Why didn’t this work?")
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
