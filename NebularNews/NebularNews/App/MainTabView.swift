import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isCompanionMode {
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
        } else {
            TabView {
                Tab("Dashboard", systemImage: "house") {
                    LocalDashboardPlaceholderView()
                }

                Tab("Articles", systemImage: "doc.text") {
                    ArticleListView()
                }

                Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                    LocalChatPlaceholderView()
                }

                Tab("More", systemImage: "ellipsis") {
                    LocalMoreView()
                }
            }
        }
    }
}

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

private struct LocalDashboardPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Dashboard",
                systemImage: "house",
                description: Text("Use standalone mode with local feeds, or connect to your Nebular News server for synced dashboard data.")
            )
            .navigationTitle("Dashboard")
        }
    }
}

private struct LocalChatPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Local article chat remains available in a later standalone pass.")
            )
            .navigationTitle("Chat")
        }
    }
}

private struct LocalMoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    FeedListView()
                } label: {
                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("More")
        }
    }
}
