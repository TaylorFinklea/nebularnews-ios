import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var articles: [Article]

    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case read = "Read"
    }

    private var filteredArticles: [Article] {
        var result = articles

        switch filterMode {
        case .all: break
        case .unread: result = result.filter { !$0.isRead }
        case .read: result = result.filter { $0.isRead }
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
                        ForEach(filteredArticles, id: \.id) { article in
                            NavigationLink(value: article.id) {
                                ArticleRow(article: article)
                            }
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
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Articles")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .searchable(text: $searchText, prompt: "Search articles")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(FilterMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: filterMode == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(filteredArticles.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            // Feed name + date
            HStack {
                if let feedTitle = article.feed?.title, !feedTitle.isEmpty {
                    Text(feedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let date = article.publishedAt {
                    Text(date.relativeDisplay)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Title
            Text(article.title ?? "Untitled")
                .font(.headline)
                .fontWeight(article.isRead ? .regular : .semibold)
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(2)

            // Excerpt
            if let excerpt = article.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Author
            if let author = article.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(article.isRead ? 0.7 : 1)
    }
}
