import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleListView: View {
    @Environment(\.modelContext) private var modelContext

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
        case .unread: result = result.filter(\.isUnreadQueueCandidate)
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
                                LabeledContent("Articles", value: "\(filteredArticles.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LabeledContent("Filter") {
                                    Picker("Filter", selection: $filterMode) {
                                        ForEach(FilterMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue)
                                                .tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reading queue")
                                    Text(filterSummaryText)
                                        .textCase(nil)
                                }
                            }

                            Section {
                                ForEach(filteredArticles, id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        StandaloneArticleRow(article: article)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            handleLeadingSwipe(for: article)
                                        } label: {
                                            swipeActionLabel(for: article)
                                        }
                                        .tint(swipeTint(for: article))
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

    private func handleLeadingSwipe(for article: Article) {
        if article.isRead {
            article.markUnread()
            try? modelContext.save()
            return
        }

        if article.isDismissed {
            article.clearDismissal()
            try? modelContext.save()
            return
        }

        let previousDismissedAt = article.dismissedAt
        article.markDismissed()
        let newDismissedAt = article.dismissedAt
        try? modelContext.save()

        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.processDismissChange(
                articleID: article.id,
                previousDismissedAt: previousDismissedAt,
                newDismissedAt: newDismissedAt
            )
        }
    }

    private func swipeActionLabel(for article: Article) -> some View {
        Label(
            swipeActionTitle(for: article),
            systemImage: swipeActionSystemImage(for: article)
        )
    }

    private func swipeActionTitle(for article: Article) -> String {
        if article.isRead {
            return "Unread"
        }
        return article.isDismissed ? "Undismiss" : "Dismiss"
    }

    private func swipeActionSystemImage(for article: Article) -> String {
        if article.isRead {
            return "envelope.badge"
        }
        return article.isDismissed ? "arrow.uturn.backward.circle" : "eye.slash"
    }

    private func swipeTint(for article: Article) -> Color {
        if article.isRead {
            return .blue
        }
        return article.isDismissed ? .orange : .secondary
    }
}
