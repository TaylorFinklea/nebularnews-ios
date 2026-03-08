import SwiftUI
import SwiftData
import NebularNewsKit

/// Today tab — a smart briefing combining stats with top-scored articles.
///
/// This is the primary landing screen, replacing the old Dashboard tab.
/// It shows a time-of-day greeting, quick stats, the top article as a
/// hero card, and a prioritized list of the next best reads.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var allArticles: [Article]

    @Query private var feeds: [Feed]

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .hero) {
                ScrollView {
                    VStack(spacing: 20) {
                        TodayBriefingHeader(stats: stats)
                        TodayQuickStats(stats: stats)

                        if let hero = topArticles.first {
                            DashboardSectionHeader(
                                title: "Top pick",
                                subtitle: "Your strongest match right now."
                            )
                            TodayHeroCard(article: hero)
                        }

                        if topArticles.count > 1 {
                            DashboardSectionHeader(
                                title: "Up next",
                                subtitle: "More high-fit articles to explore."
                            )

                            ForEach(topArticles.dropFirst(), id: \.id) { article in
                                NavigationLink(value: article.id) {
                                    CompactArticleRow(article: article)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(showsDismissButton: true)
                }
            }
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
        }
    }

    // MARK: - Computed

    private var stats: TodayStats {
        TodayStats.compute(articles: allArticles, feedCount: feeds.count)
    }

    private var topArticles: [Article] {
        allArticles
            .filter { $0.isUnreadQueueCandidate && $0.hasReadyScore && $0.score != nil }
            .sorted {
                if ($0.score ?? 0) == ($1.score ?? 0) {
                    return ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
                }
                return ($0.score ?? 0) > ($1.score ?? 0)
            }
            .prefix(10)
            .map { $0 }
    }
}
