import SwiftUI
import SwiftData
import NebularNewsKit

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Article> { $0.readingListAddedAt != nil })
    private var readingListArticles: [Article]

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
            .badge(readingListArticles.count)

            Tab("Discover", systemImage: "safari") {
                DiscoverView()
            }
        }
    }

    // MARK: - Companion Mode (unchanged)

    private var companionTabs: some View {
        TabView {
            Tab("Dashboard", systemImage: "house") {
                CompanionDashboardView()
            }

            Tab("Articles", systemImage: "doc.text") {
                CompanionArticlesView()
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                CompanionChatPlaceholderView()
            }

            Tab("More", systemImage: "ellipsis") {
                CompanionMoreView()
            }
        }
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
