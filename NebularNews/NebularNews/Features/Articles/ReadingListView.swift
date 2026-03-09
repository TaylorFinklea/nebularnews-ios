import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

struct ReadingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var filterMode: ReadingListFilterMode = .all
    @State private var viewModel = ReadingListBrowseViewModel()

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                Group {
                    if viewModel.isLoading && viewModel.savedArticles.isEmpty && viewModel.pendingSavedCount == 0 {
                        ReadingListSkeletonView()
                    } else if viewModel.totalSavedCount == 0 {
                        ContentUnavailableView(
                            "Reading List Empty",
                            systemImage: "bookmark",
                            description: Text("Save articles from the article toolbar to keep them here for later.")
                        )
                    } else if viewModel.savedArticles.isEmpty && viewModel.pendingSavedCount == 0 {
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

                            if viewModel.pendingSavedCount > 0 {
                                Section {
                                    ForEach(0..<min(3, viewModel.pendingSavedCount), id: \.self) { _ in
                                        ReadingListSkeletonRow()
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                    }
                                } header: {
                                    Text("Preparing \(viewModel.pendingSavedCount) saved article\(viewModel.pendingSavedCount == 1 ? "" : "s")")
                                }
                            }

                            Section {
                                ForEach(viewModel.savedArticles, id: \.id) { article in
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
            .task(id: reloadKey) {
                await viewModel.reload(
                    container: modelContext.container,
                    searchText: searchText,
                    filterMode: filterMode
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                Task {
                    await viewModel.reload(
                        container: modelContext.container,
                        searchText: searchText,
                        filterMode: filterMode
                    )
                }
            }
        }
    }

    private var reloadKey: String {
        "\(filterMode.rawValue)|\(searchText)"
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

                    Text("\(viewModel.savedArticles.count)")
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
        Task {
            await viewModel.removeFromReadingList(
                articleID: article.id,
                container: modelContext.container
            )
        }
    }
}

private struct ReadingListSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<4, id: \.self) { _ in
                ReadingListSkeletonRow()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct ReadingListSkeletonRow: View {
    var body: some View {
        GlassCard(cornerRadius: 22, style: .raised) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.18))
                    .frame(width: 160, height: 12)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.26))
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.16))
                    .frame(width: 220, height: 16)
            }
            .redacted(reason: .placeholder)
        }
    }
}

@Observable
@MainActor
private final class ReadingListBrowseViewModel {
    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0

    var savedArticles: [Article] = []
    var pendingSavedCount = 0
    var totalSavedCount = 0
    var isLoading = false

    func reload(
        container: ModelContainer,
        searchText: String,
        filterMode: ReadingListFilterMode
    ) async {
        let articleRepo = repository(for: container)
        requestToken += 1
        let token = requestToken
        isLoading = true

        let savedFilter: ArticleFilter = {
            var filter = ArticleFilter()
            filter.readingListOnly = true
            return filter
        }()

        let pendingSavedFilter: ArticleFilter = {
            var filter = savedFilter
            filter.presentationFilter = .pendingOnly
            return filter
        }()

        async let savedArticles = articleRepo.listVisibleArticles(
            filter: savedFilter,
            sort: .newest,
            limit: 500,
            offset: 0
        )
        async let totalSavedCount = articleRepo.count(filter: savedFilter)
        async let pendingSavedCount = articleRepo.count(filter: pendingSavedFilter)

        let visibleSavedArticles = await savedArticles
        let totalCount = await totalSavedCount
        let pendingCount = await pendingSavedCount

        guard token == requestToken else { return }

        self.savedArticles = ReadingListContent.filteredArticles(
            from: visibleSavedArticles,
            searchText: searchText,
            filterMode: filterMode
        )
        self.totalSavedCount = totalCount
        self.pendingSavedCount = pendingCount
        isLoading = false
    }

    func removeFromReadingList(articleID: String, container: ModelContainer) async {
        let articleRepo = repository(for: container)
        try? await articleRepo.setReadingList(id: articleID, isSaved: false)
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo {
            return articleRepo
        }

        let articleRepo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = articleRepo
        return articleRepo
    }
}
