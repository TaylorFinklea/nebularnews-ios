import SwiftUI
import NebularNewsKit

struct CompanionTodayView: View {
    @Environment(AppState.self) private var appState

    @Binding var showSettings: Bool

    @State private var payload: CompanionTodayPayload?
    @State private var errorMessage = ""
    @State private var isLoading = false

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
                            StatPill(label: "Unread", value: "\(payload.stats.unreadTotal)")
                            StatPill(label: "New today", value: "\(payload.stats.newToday)")
                            StatPill(label: "High fit", value: "\(payload.stats.highFitUnread)")
                        }
                        .padding(.horizontal)

                        // Hero card
                        if let hero = payload.hero {
                            NavigationLink(destination: CompanionArticleDetailView(articleId: hero.id)) {
                                TodayHeroCardView(article: hero)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        // News brief
                        if let newsBrief = payload.newsBrief, appState.features?.newsBrief == true {
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
                        }

                        // Up next
                        if !payload.upNext.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Up next")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(payload.upNext) { article in
                                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                                        CompactUpNextRow(article: article)
                                    }
                                    .buttonStyle(.plain)
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
                _ = try? await appState.mobileAPI.triggerPull()
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

    private func loadToday() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.mobileAPI.fetchToday()
            payload = result
            errorMessage = ""
            await CompanionCache.shared.store(result, category: .today)
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

private struct TodayHeroCardView: View {
    let article: CompanionArticleListItem

    var body: some View {
        GlassImageCard(style: .hero) {
            ZStack(alignment: .bottomLeading) {
                if let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Rectangle().fill(Color(.tertiarySystemFill))
                        }
                    }
                    .frame(height: 220)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 220)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    if let score = article.score {
                        ScoreBadge(score: score)
                    }
                    Text(article.title ?? "Untitled")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    if let source = article.sourceName {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
            }
        }
    }
}

private struct CompactUpNextRow: View {
    let article: CompanionArticleListItem

    var body: some View {
        HStack(spacing: 12) {
            ScoreAccentBar(score: article.score, isRead: article.isRead == 1, width: 3)
                .frame(height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.title ?? "Untitled")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let source = article.sourceName {
                        Text(source)
                    }
                    if let score = article.score {
                        Text("\(score)/5")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }
}
