import SwiftUI
import NebularNewsKit

struct CompanionTodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(AIAssistantCoordinator.self) private var aiAssistant

    @Binding var showSettings: Bool

    @State private var payload: CompanionTodayPayload?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isGeneratingBrief = false
    @State private var deepLinkArticleId: String?
    @State private var showBriefHistory = false
    @State private var deepLinkBriefId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !errorMessage.isEmpty && payload == nil {
                        ErrorBanner(message: errorMessage) { Task { await loadToday() } }
                    }

                    if let payload {
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage) { Task { await loadToday() } }
                        }

                        // Quick stats
                        HStack(spacing: 12) {
                            NavigationLink(destination: CompanionFilteredArticleListView(
                                title: "Unread",
                                read: .unread,
                                sort: .unreadFirst,
                                sinceDays: nil,
                                minScore: nil
                            )) {
                                StatPill(label: "Unread", value: "\(payload.stats.unreadTotal)")
                            }
                            NavigationLink(destination: CompanionFilteredArticleListView(
                                title: "Last 24 Hours",
                                read: .unread,
                                sort: .unreadFirst,
                                sinceDays: 1,
                                minScore: nil
                            )) {
                                StatPill(label: "Last 24h", value: "\(payload.stats.newToday)")
                            }
                            NavigationLink(destination: CompanionFilteredArticleListView(
                                title: "High Fit",
                                read: .unread,
                                sort: .unreadFirst,
                                sinceDays: 7,
                                minScore: 3
                            )) {
                                StatPill(label: "High fit", value: "\(payload.stats.highFitUnread)")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)

                        // Resume reading — shown when there's an in-progress article.
                        if let resume = payload.resume {
                            NavigationLink(destination: CompanionArticleDetailView(articleId: resume.articleId)) {
                                ResumeReadingCard(resume: resume)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        // Hero card
                        if let hero = payload.hero {
                            NavigationLink(destination: CompanionArticleDetailView(articleId: hero.id)) {
                                ArticleCard(article: hero, style: .hero)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        // News brief
                        if let newsBrief = payload.newsBrief {
                            GlassCard(style: .standard) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(newsBrief.title)
                                        .font(.headline)
                                    Text(newsBrief.editionLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(newsBrief.bullets) { bullet in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("• \(bullet.text)")
                                                .font(.subheadline)
                                            ForEach(bullet.sources) { source in
                                                NavigationLink(destination: CompanionArticleDetailView(articleId: source.articleId)) {
                                                    Text(source.title ?? "Source")
                                                        .font(.caption)
                                                        .foregroundStyle(.accent)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            Button {
                                Task { await generateBrief() }
                            } label: {
                                GlassCard(style: .standard) {
                                    HStack {
                                        Image(systemName: "newspaper.fill")
                                            .foregroundStyle(.secondary)
                                        if isGeneratingBrief {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Generating brief...")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Generate News Brief")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isGeneratingBrief)
                            .padding(.horizontal)
                        }

                        // Empty state
                        if payload.hero == nil && payload.upNext.isEmpty {
                            ContentUnavailableView(
                                "No articles yet",
                                systemImage: "newspaper",
                                description: Text("Articles will appear here once your feeds are polled. Pull to refresh.")
                            )
                            .padding(.top, 20)
                        }

                        // Up next
                        if !payload.upNext.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Up next")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(payload.upNext) { article in
                                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                                        ArticleCard(article: article, style: .compact)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .overlay {
                if isLoading && payload == nil {
                    ProgressView("Loading today…")
                }
            }
            .navigationTitle("Today")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBriefHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Brief history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button { showBriefHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
                #endif
            }
            .sheet(isPresented: $showBriefHistory) {
                BriefHistoryView()
            }
            .navigationDestination(item: $deepLinkBriefId) { briefId in
                BriefDetailView(briefId: briefId)
            }
            .refreshable {
                try? await appState.supabase.triggerPull()
                try? await Task.sleep(for: .seconds(2))
                await loadToday()
            }
            .task {
                // Show cached data immediately
                if payload == nil {
                    payload = await CompanionCache.shared.load(CompanionTodayPayload.self, category: .today)
                }
                await loadToday()
            }
            .navigationDestination(item: $deepLinkArticleId) { articleId in
                CompanionArticleDetailView(articleId: articleId)
            }
            .onChange(of: deepLinkRouter.pendingArticleId) { _, newValue in
                if let articleId = newValue {
                    deepLinkArticleId = articleId
                    deepLinkRouter.clearPendingArticle()
                }
            }
            .onChange(of: deepLinkRouter.pendingBriefId) { _, newValue in
                if let briefId = newValue {
                    deepLinkBriefId = briefId
                    deepLinkRouter.clearPendingBrief()
                }
            }
            .onAppear {
                // Handle deep link that arrived before this view appeared
                if let articleId = deepLinkRouter.pendingArticleId {
                    deepLinkArticleId = articleId
                    deepLinkRouter.clearPendingArticle()
                }
                if let briefId = deepLinkRouter.pendingBriefId {
                    deepLinkBriefId = briefId
                    deepLinkRouter.clearPendingBrief()
                }
                // Handle AI-triggered brief generation that was queued before we mounted
                observePendingBriefGeneration(appState.pendingBriefGeneration)
            }
            .onChange(of: appState.pendingBriefGeneration) { _, newValue in
                observePendingBriefGeneration(newValue)
            }
        }
    }

    private func observePendingBriefGeneration(_ newValue: Bool) {
        guard newValue else { return }
        appState.pendingBriefGeneration = false
        Task { await generateBrief() }
    }

    private func generateBrief() async {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        #if os(iOS)
        let editionLabel = Calendar.current.component(.hour, from: Date()) < 12 ? "Morning Brief" : "Evening Brief"
        let activity = BriefLiveActivityController.start(editionLabel: editionLabel)
        #endif

        do {
            let brief = try await appState.supabase.generateNewsBrief()
            if let brief {
                let newPayload = CompanionTodayPayload(
                    hero: payload?.hero,
                    upNext: payload?.upNext ?? [],
                    stats: payload?.stats ?? CompanionTodayStats(unreadTotal: 0, newToday: 0, highFitUnread: 0),
                    newsBrief: brief,
                    resume: payload?.resume
                )
                payload = newPayload
                WidgetDataWriter.updateFromToday(
                    stats: newPayload.stats,
                    hero: newPayload.hero,
                    upNext: newPayload.upNext,
                    newsBrief: brief
                )
                // Auto-open the generated brief in the detail view when the
                // generation was user-initiated ("Preview next brief" or the
                // Generate button). The brief id is present on the response
                // since backend now returns it from /brief/generate.
                if let briefId = brief.id {
                    deepLinkRouter.pendingBriefId = briefId
                }
                #if os(iOS)
                await BriefLiveActivityController.finish(
                    activity: activity,
                    firstBullet: brief.bullets.first?.text,
                    bulletCount: brief.bullets.count
                )
                #endif
            } else {
                #if os(iOS)
                await BriefLiveActivityController.fail(activity: activity)
                #endif
            }
        } catch {
            errorMessage = error.localizedDescription
            #if os(iOS)
            await BriefLiveActivityController.fail(activity: activity)
            #endif
        }
    }

    private func loadToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.supabase.fetchToday()

            // Cache today's articles in SwiftData for offline access (uncapped — cache mirrors server)
            if let cache = appState.articleCache {
                var todayArticles: [CompanionArticleListItem] = []
                if let hero = result.hero { todayArticles.append(hero) }
                todayArticles.append(contentsOf: result.upNext)
                for item in todayArticles {
                    cache.updateArticleFromListItem(item)
                }
            }

            // Apply per-feed daily caps to upNext (hero is the editorial pick, never capped).
            let cappedUpNext = applyFeedCaps(to: result.upNext)
            let cappedResult = CompanionTodayPayload(
                hero: result.hero,
                upNext: cappedUpNext,
                stats: result.stats,
                newsBrief: result.newsBrief,
                resume: result.resume
            )
            payload = cappedResult
            errorMessage = ""
            await CompanionCache.shared.store(cappedResult, category: .today)

            // Update Home Screen widgets with capped data so widgets respect the cap too
            WidgetDataWriter.updateFromToday(
                stats: cappedResult.stats,
                hero: cappedResult.hero,
                upNext: cappedResult.upNext,
                newsBrief: cappedResult.newsBrief
            )
            pushAssistantContext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyFeedCaps(to articles: [CompanionArticleListItem]) -> [CompanionArticleListItem] {
        guard let cache = appState.articleCache else { return articles }
        let pairs = cache.getCachedFeeds().compactMap { feed -> (String, Int)? in
            guard let cap = feed.maxArticlesPerDay, cap > 0 else { return nil }
            return (feed.id, cap)
        }
        let caps = Dictionary(uniqueKeysWithValues: pairs)
        return PerFeedDailyCapFilter.apply(articles, caps: caps)
    }

    private func pushAssistantContext() {
        guard let p = payload else { return }
        let articleRefs: [AIArticleRef] = p.upNext.prefix(5).map { a in
            AIArticleRef(id: a.id, title: a.title ?? "Untitled", score: a.score, source: a.sourceName)
        }
        let briefText = p.newsBrief?.bullets.map(\.text).joined(separator: ". ")
        aiAssistant.updateContext(AIPageContext(
            pageType: "today",
            pageLabel: "Today",
            articles: articleRefs,
            stats: AIPageStats(
                unreadCount: p.stats.unreadTotal,
                totalCount: nil,
                newToday: p.stats.newToday
            ),
            briefSummary: briefText
        ))
    }
}

// MARK: - Today subviews

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .modifier(GlassRoundedBackground(cornerRadius: 12))
    }
}
