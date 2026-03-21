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

    @Binding var showSettings: Bool

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
            }
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
    @State private var isSaved = false
    @State private var savingBookmark = false

    var body: some View {
        Group {
            if isLoading && payload == nil {
                ProgressView("Loading article…")
            } else if let payload {
                List {
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
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            case .empty:
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .overlay { ProgressView() }
            @unknown default:
                EmptyView()
            }
        }
        .frame(height: baseHeight)
        .clipped()
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
    @Environment(ThemeManager.self) private var themeManager
    @State private var settings: CompanionSettingsPayload?
    @State private var error: String?
    @State private var isLoading = true

    private static let pollIntervalRange = [5, 10, 15, 30, 60]
    private static let summaryStyles = ["concise", "detailed", "bullet"]
    private static let scoringMethods = ["ai", "algorithmic", "hybrid"]

    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red).font(.callout) }
            }

            if let settings {
                Section("Server") {
                    Picker("Poll interval", selection: pollIntervalBinding(settings)) {
                        ForEach(Self.pollIntervalRange, id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    Picker("Summary style", selection: summaryStyleBinding(settings)) {
                        ForEach(Self.summaryStyles, id: \.self) { style in
                            Text(style.capitalized).tag(style)
                        }
                    }
                    Picker("Scoring method", selection: scoringMethodBinding(settings)) {
                        ForEach(Self.scoringMethods, id: \.self) { method in
                            Text(method.capitalized).tag(method)
                        }
                    }
                }

                Section("News Brief") {
                    Toggle("Enabled", isOn: newsBriefEnabledBinding(settings))
                }
            }

            Section("Appearance") {
                @Bindable var tm = themeManager
                Picker("Theme", selection: $tm.mode) {
                    ForEach(ThemeManager.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("Connection") {
                LabeledContent("Server", value: appState.companionServerURL?.absoluteString ?? "Not connected")
                Button("Disconnect server", role: .destructive) {
                    appState.disconnectCompanion()
                }
            }
        }
        .navigationTitle("Settings")
        .overlay { if isLoading { ProgressView() } }
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        isLoading = true
        error = nil
        do {
            settings = try await appState.mobileAPI.fetchSettings()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ mutate: (inout CompanionSettingsPayload) -> Void) {
        guard var draft = settings else { return }
        mutate(&draft)
        settings = draft
        Task {
            do {
                settings = try await appState.mobileAPI.updateSettings(body: draft)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func pollIntervalBinding(_ current: CompanionSettingsPayload) -> Binding<Int> {
        Binding(
            get: { current.pollIntervalMinutes },
            set: { val in save { $0.pollIntervalMinutes = val } }
        )
    }

    private func summaryStyleBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.summaryStyle },
            set: { val in save { $0.summaryStyle = val } }
        )
    }

    private func scoringMethodBinding(_ current: CompanionSettingsPayload) -> Binding<String> {
        Binding(
            get: { current.scoringMethod },
            set: { val in save { $0.scoringMethod = val } }
        )
    }

    private func newsBriefEnabledBinding(_ current: CompanionSettingsPayload) -> Binding<Bool> {
        Binding(
            get: { current.newsBriefConfig.enabled },
            set: { val in save { $0.newsBriefConfig.enabled = val } }
        )
    }
}

// MARK: - Shared subviews

private struct ArticleRow: View {
    let article: CompanionArticleListItem

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
                        Color(.tertiarySystemFill)
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
