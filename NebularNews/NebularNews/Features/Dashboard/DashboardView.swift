import SwiftUI
import NebularNewsKit

/// Dashboard view showing reading momentum, top-scored articles, and quick stats.
///
/// Ported from the standalone-era `StandaloneDashboardView`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData `@Query`.
struct DashboardView: View {
    @Environment(AppState.self) private var appState

    @State private var todayPayload: CompanionTodayPayload?
    @State private var topUnread: [CompanionArticleListItem] = []
    @State private var feedCount = 0
    @State private var totalArticles = 0
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showMultiChat = false

    // MARK: - Computed Stats

    private var unreadCount: Int {
        todayPayload?.stats.unreadTotal ?? 0
    }

    private var newToday: Int {
        todayPayload?.stats.newToday ?? 0
    }

    private var highFitUnread: Int {
        todayPayload?.stats.highFitUnread ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !errorMessage.isEmpty && todayPayload == nil {
                        ErrorBanner(message: errorMessage) {
                            Task { await loadDashboard() }
                        }
                    }

                    // Momentum section
                    momentumSection

                    // Ask about today's news
                    Button {
                        showMultiChat = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "newspaper")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask about today's news")
                                    .font(.subheadline.weight(.medium))
                                Text("Get insights across your recent articles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // Top scored articles
                    if !topUnread.isEmpty {
                        topArticlesSection
                    }

                    // Stats summary
                    statsSection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .overlay {
                if isLoading && todayPayload == nil {
                    ProgressView()
                }
            }
            .sheet(isPresented: $showMultiChat) {
                MultiArticleChatView()
            }
            .refreshable {
                await loadDashboard()
            }
            .task {
                if todayPayload == nil {
                    await loadDashboard()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = ""

        do {
            async let todayTask = appState.supabase.fetchToday()
            async let topTask = appState.supabase.fetchArticles(
                limit: PaginationConfig.dashboardPageSize,
                read: .unread,
                minScore: 4,
                sort: .score,
                sinceDays: 7
            )
            async let feedsTask = appState.supabase.fetchFeeds()

            let today = try await todayTask
            let topPayload = try await topTask
            let feeds = try await feedsTask

            todayPayload = today
            topUnread = topPayload.articles
            feedCount = feeds.count
            totalArticles = topPayload.total

            // Update Home Screen widgets with fresh data
            WidgetDataWriter.updateFromToday(
                stats: today.stats,
                hero: today.hero,
                upNext: today.upNext,
                newsBrief: today.newsBrief
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Momentum

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reading Momentum", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Unread",
                    value: "\(unreadCount)",
                    icon: "envelope.badge",
                    color: unreadCount > 0 ? .blue : .secondary
                )
                MetricCard(
                    title: "New Today",
                    value: "\(newToday)",
                    icon: "clock",
                    color: newToday > 0 ? .orange : .secondary
                )
                MetricCard(
                    title: "Total",
                    value: "\(totalArticles)",
                    icon: "doc.text",
                    color: .secondary
                )
                MetricCard(
                    title: "High Fit",
                    value: "\(highFitUnread)",
                    icon: "star.fill",
                    color: highFitUnread > 0 ? Color.forScore(5) : .secondary
                )
            }
        }
    }

    // MARK: - Top Articles

    private var topArticlesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Unread", systemImage: "arrow.up.right")
                .font(.headline)

            ForEach(topUnread) { article in
                NavigationLink(destination: ArticleDetailView(articleId: article.id)) {
                    HStack(spacing: 10) {
                        ScoreBadge(score: article.score)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title ?? "Untitled")
                                .font(.subheadline)
                                .lineLimit(2)
                            if let source = article.sourceName {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let publishedAt = article.publishedAt {
                            Text(Date(timeIntervalSince1970: Double(publishedAt) / 1000).relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Overview", systemImage: "chart.pie")
                .font(.headline)

            HStack(spacing: 16) {
                DashboardStatPill(label: "Articles", value: "\(totalArticles)")
                DashboardStatPill(label: "Feeds", value: "\(feedCount)")
                DashboardStatPill(label: "High Fit", value: "\(highFitUnread)")
            }
        }
    }
}

// MARK: - Supporting Views

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DashboardStatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
