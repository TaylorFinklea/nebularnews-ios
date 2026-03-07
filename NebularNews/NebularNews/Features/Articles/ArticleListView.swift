import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var articles: [Article]

    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all

    /// Optional feed filter — when set, only shows articles from this feed.
    /// Set via navigation from FeedListView.
    let feedId: String?
    let feedTitle: String?

    init(feedId: String? = nil, feedTitle: String? = nil) {
        self.feedId = feedId
        self.feedTitle = feedTitle
    }

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case read = "Read"
        case scored = "Scored"
        case learning = "Learning"
    }

    private var filteredArticles: [Article] {
        var result = articles

        if let feedId {
            result = result.filter { $0.feed?.id == feedId }
        }

        switch filterMode {
        case .all: break
        case .unread: result = result.filter { !$0.isRead }
        case .read: result = result.filter { $0.isRead }
        case .scored: result = result.filter(\.hasReadyScore)
        case .learning: result = result.filter(\.isLearningScore)
        }

        if !searchText.isEmpty {
            result = result.filter { article in
                article.title?.localizedCaseInsensitiveContains(searchText) == true ||
                article.excerpt?.localizedCaseInsensitiveContains(searchText) == true ||
                article.author?.localizedCaseInsensitiveContains(searchText) == true ||
                article.feed?.title.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return result
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                Group {
                    if articles.isEmpty {
                        ContentUnavailableView(
                            "No Articles Yet",
                            systemImage: "doc.text",
                            description: Text("Go to More → Feeds to add an RSS feed, then pull to refresh.")
                        )
                    } else if filteredArticles.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            Section {
                                articleFilterHeader
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                            Section {
                                ForEach(filteredArticles, id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        ArticleRow(article: article)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toggleRead(article)
                                        } label: {
                                            Label(
                                                article.isRead ? "Unread" : "Read",
                                                systemImage: article.isRead ? "envelope.badge" : "envelope.open"
                                            )
                                        }
                                        .tint(article.isRead ? .blue : .green)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(feedTitle ?? "Articles")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .searchable(text: $searchText, prompt: "Search articles")
        }
    }

    private var articleFilterHeader: some View {
        GlassCard(cornerRadius: 24, style: .raised, tintColor: filterMode == .all ? nil : palette.primary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading queue")
                            .font(.title3.bold())
                        Text(filterSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(filteredArticles.count)")
                        .font(.headline.bold())
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(palette.primarySoft, in: Capsule())
                        .overlay(Capsule().strokeBorder(palette.primary.opacity(0.16)))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilterMode.allCases, id: \.self) { mode in
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    filterMode = mode
                                }
                            } label: {
                                Text(mode.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .background(
                                        (filterMode == mode ? palette.primarySoft : palette.surfaceSoft),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                filterMode == mode
                                                ? palette.primary.opacity(0.22)
                                                : palette.surfaceBorder.opacity(0.7)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(filterMode == mode ? palette.primary : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var filterSummaryText: String {
        switch filterMode {
        case .all:
            return "Everything available across your current feeds."
        case .unread:
            return "Only unread stories that still need attention."
        case .read:
            return "Stories you already worked through."
        case .scored:
            return "Items with a ready fit score."
        case .learning:
            return "Items still gathering preference signals."
        }
    }

    private func toggleRead(_ article: Article) {
        article.isRead.toggle()
        article.readAt = article.isRead ? Date() : nil
        try? modelContext.save()
    }
}

// MARK: - Article Row

private struct ArticleRow: View {
    let article: Article

    var body: some View {
        GlassCard(cornerRadius: 22, style: article.isRead ? .standard : .raised, tintColor: accentColor) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                            Text(feedTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if article.hasReadyScore, let score = article.score {
                            ScoreBadge(score: score)
                        } else if article.isLearningScore {
                            LearningBadge()
                        }

                        if let date = article.publishedAt {
                            Text(date.relativeDisplay)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text(article.title ?? "Untitled")
                        .font(.headline)
                        .fontWeight(article.isRead ? .regular : .semibold)
                        .foregroundStyle(article.isRead ? .secondary : .primary)
                        .lineLimit(2)

                    if let summary = article.summaryText, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let excerpt = article.excerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let author = article.author, !author.isEmpty {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .opacity(article.isRead ? 0.82 : 1)
    }

    private var accentColor: Color {
        if article.hasReadyScore, let score = article.score {
            return Color.forScore(score)
        }
        if article.isLearningScore {
            return .purple
        }
        return article.isRead ? .secondary : .cyan
    }
}

private struct LearningBadge: View {
    var body: some View {
        Text("Learning")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.purple.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.purple.opacity(0.18)))
    }
}
