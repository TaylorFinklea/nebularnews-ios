import SwiftUI
import SwiftData
import NebularNewsKit

struct ReadingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(
        filter: #Predicate<Article> { $0.readingListAddedAt != nil },
        sort: [
            SortDescriptor(\Article.readingListAddedAt, order: .reverse),
            SortDescriptor(\Article.publishedAt, order: .reverse)
        ]
    )
    private var savedArticles: [Article]

    @State private var searchText = ""
    @State private var filterMode: ReadingListFilterMode = .all

    private var filteredArticles: [Article] {
        ReadingListContent.filteredArticles(
            from: savedArticles,
            searchText: searchText,
            filterMode: filterMode
        )
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                Group {
                    if savedArticles.isEmpty {
                        ContentUnavailableView(
                            "Reading List Empty",
                            systemImage: "bookmark",
                            description: Text("Save articles from the article toolbar to keep them here for later.")
                        )
                    } else if filteredArticles.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                emptyStateTitle,
                                systemImage: "bookmark.slash",
                                description: Text(emptyStateDescription)
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        List {
                            Section {
                                readingListHeader
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                            Section {
                                ForEach(filteredArticles, id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        StandaloneArticleRow(article: article)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing) {
                                        Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                                            removeFromReadingList(article)
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Reading List")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .searchable(text: $searchText, prompt: "Search saved articles")
        }
    }

    private var readingListHeader: some View {
        GlassCard(cornerRadius: 24, style: .raised, tintColor: filterMode == .all ? nil : palette.primary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saved for later")
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

                HStack(spacing: 8) {
                    ForEach(ReadingListFilterMode.allCases, id: \.self) { mode in
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

    private var filterSummaryText: String {
        switch filterMode {
        case .all:
            return "Everything you saved across the app."
        case .unread:
            return "Saved articles you still haven't opened."
        case .read:
            return "Saved articles you've already read."
        }
    }

    private var emptyStateTitle: String {
        switch filterMode {
        case .all:
            return "Reading List Empty"
        case .unread:
            return "No Unread Saves"
        case .read:
            return "No Read Saves"
        }
    }

    private var emptyStateDescription: String {
        switch filterMode {
        case .all:
            return "Save articles from the article toolbar to keep them here for later."
        case .unread:
            return "All saved articles have already been read."
        case .read:
            return "No saved articles have been marked read yet."
        }
    }

    private func removeFromReadingList(_ article: Article) {
        article.removeFromReadingList()
        try? modelContext.save()
    }
}
