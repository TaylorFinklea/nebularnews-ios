import SwiftUI
import NebularNewsKit

struct CompanionTodayView: View {
    @Environment(AppState.self) private var appState

    @Binding var showSettings: Bool

    @State private var payload: CompanionTodayPayload?
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isGeneratingBrief = false

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
                                                    Text(source.title)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
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
        }
    }

    private func generateBrief() async {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }
        do {
            let brief = try await appState.supabase.generateNewsBrief()
            if let brief {
                payload = CompanionTodayPayload(
                    hero: payload?.hero,
                    upNext: payload?.upNext ?? [],
                    stats: payload?.stats ?? CompanionTodayStats(unreadTotal: 0, newToday: 0, highFitUnread: 0),
                    newsBrief: brief
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.supabase.fetchToday()
            payload = result
            errorMessage = ""
            await CompanionCache.shared.store(result, category: .today)

            // Cache today's articles in SwiftData for offline access
            if let cache = appState.articleCache {
                var todayArticles: [CompanionArticleListItem] = []
                if let hero = result.hero { todayArticles.append(hero) }
                todayArticles.append(contentsOf: result.upNext)
                for item in todayArticles {
                    cache.updateArticleFromListItem(item)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
