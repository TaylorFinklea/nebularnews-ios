import SwiftUI
import NebularNewsKit

/// Articles the user has actually opened with foreground engagement,
/// newest-read first. Powered by `GET /api/articles?sort=recent_reads`,
/// which filters last_read_at IS NOT NULL — so a brief seeing a title
/// won't surface here, but tapping in and reading the article will.
///
/// Pushed onto Library's NavigationStack via the "Reading history" row.
struct ReadHistoryView: View {
    @Environment(AppState.self) private var appState

    @State private var articles: [CompanionArticleListItem] = []
    @State private var offset: Int = 0
    @State private var hasMore: Bool = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var query: String = ""

    private let pageSize = 30

    private var filtered: [CompanionArticleListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return articles }
        return articles.filter { article in
            (article.title ?? "").localizedCaseInsensitiveContains(trimmed)
                || (article.sourceName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if articles.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "No reading history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Open an article and read for a few seconds — it'll appear here so you can find it later.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedByDay(), id: \.0) { header, rows in
                    Section(header: Text(header)) {
                        ForEach(rows) { article in
                            NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                                row(for: article)
                            }
                        }
                    }
                }
                if hasMore {
                    loadMoreRow
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search history")
        .navigationTitle("Reading history")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await reload() }
        .task { if articles.isEmpty { await reload() } }
        .overlay {
            if isLoading && articles.isEmpty {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func row(for article: CompanionArticleListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "Untitled")
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                if let source = article.sourceName {
                    Text(source)
                        .lineLimit(1)
                }
                if let lastReadAt = article.lastReadAt {
                    Text("·")
                    Text(relativeReadAt(lastReadAt))
                }
                if let ms = article.timeSpentMsTotal, ms > 0 {
                    Text("·")
                    Text(timeSpentLabel(ms))
                }
                Spacer()
                if let score = article.score {
                    Text("\(score)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.forScore(score))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
            } else {
                Button("Load older") {
                    Task { await loadMore() }
                }
                .font(.caption)
            }
            Spacer()
        }
        .task { await loadMore() }
    }

    // MARK: - Grouping

    private func groupedByDay() -> [(String, [CompanionArticleListItem])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        var buckets: [(String, [CompanionArticleListItem])] = []
        var current: (String, [CompanionArticleListItem])?

        for article in filtered {
            // Anchor to lastReadAt; if missing (shouldn't happen given the
            // server filter, but defensive), bucket under "Earlier".
            let label: String
            if let lastReadAt = article.lastReadAt {
                let date = Date(timeIntervalSince1970: TimeInterval(lastReadAt) / 1000)
                let day = calendar.startOfDay(for: date)
                if day == today {
                    label = "Today"
                } else if day == yesterday {
                    label = "Yesterday"
                } else {
                    label = formatter.string(from: day)
                }
            } else {
                label = "Earlier"
            }

            if current?.0 == label {
                current!.1.append(article)
            } else {
                if let c = current { buckets.append(c) }
                current = (label, [article])
            }
        }
        if let c = current { buckets.append(c) }
        return buckets
    }

    // MARK: - Formatters

    private func relativeReadAt(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func timeSpentLabel(_ ms: Int) -> String {
        let minutes = max(1, Int(round(Double(ms) / 60_000.0)))
        return "\(minutes)m read"
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.supabase.fetchArticles(
                offset: 0,
                limit: pageSize,
                sort: .recentReads
            )
            articles = payload.articles
            offset = payload.articles.count
            hasMore = payload.articles.count == pageSize
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.supabase.fetchArticles(
                offset: offset,
                limit: pageSize,
                sort: .recentReads
            )
            let existing = Set(articles.map(\.id))
            let new = payload.articles.filter { !existing.contains($0.id) }
            articles.append(contentsOf: new)
            offset += payload.articles.count
            hasMore = payload.articles.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
