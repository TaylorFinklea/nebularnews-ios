import SwiftUI
import SwiftData
import NebularNewsKit

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var readingListCount = 0

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            NebularBackdrop()

            if appState.isCompanionMode {
                companionTabs
            } else {
                standaloneTabs
            }
        }
        .tint(palette.primary)
        .task {
            await reloadReadingListCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.readingListChanged)) { _ in
            Task { await reloadReadingListCount() }
        }
    }

    // MARK: - Standalone: Today / Feed / Reading List / Discover

    private var standaloneTabs: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView()
            }

            Tab("Feed", systemImage: "doc.richtext") {
                FeedTabView()
            }

            Tab("Reading List", systemImage: "bookmark") {
                ReadingListView()
            }
            .badge(readingListCount)

            Tab("Discover", systemImage: "safari") {
                DiscoverView()
            }
        }
    }

    // MARK: - Companion Mode

    private var companionTabs: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                CompanionTodayView()
            }

            Tab("Feed", systemImage: "doc.text") {
                CompanionArticlesView()
            }

            Tab("Reading List", systemImage: "bookmark") {
                CompanionReadingListView()
            }
            .badge(companionSavedCount)

            Tab("More", systemImage: "ellipsis") {
                CompanionMoreView()
            }
        }
        .task {
            await loadCompanionSavedCount()
        }
    }

    @State private var companionSavedCount = 0

    private func loadCompanionSavedCount() async {
        guard appState.isCompanionMode else { return }
        if let payload = try? await appState.mobileAPI.fetchSavedArticles(limit: 0) {
            companionSavedCount = payload.total
        }
    }

    private func reloadReadingListCount() async {
        let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
        var filter = ArticleFilter()
        filter.readingListOnly = true
        readingListCount = await articleRepo.count(filter: filter)
    }
}

// MARK: - Companion Placeholders

private struct CompanionChatPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Server-backed article chat stays on the web app for the first companion release.")
            )
            .navigationTitle("Chat")
        }
    }
}
