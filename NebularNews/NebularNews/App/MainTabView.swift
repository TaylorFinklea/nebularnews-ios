import SwiftUI

/// Root navigation — 4-tab Liquid Glass tab bar.
///
/// On iOS 26, TabView automatically adopts the translucent glass material.
/// The tab bar shrinks on scroll and expands on tap.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "house") {
                DashboardView()
            }

            Tab("Articles", systemImage: "doc.text") {
                ArticleListView()
            }

            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatPlaceholderView()
            }

            Tab("More", systemImage: "ellipsis") {
                MoreView()
            }
        }
    }
}

// MARK: - Placeholder Views (to be replaced in later phases)

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Dashboard",
                systemImage: "house",
                description: Text("Your reading dashboard will appear here.")
            )
            .navigationTitle("Dashboard")
        }
    }
}

struct ArticleListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Articles",
                systemImage: "doc.text",
                description: Text("Add some feeds to start reading.")
            )
            .navigationTitle("Articles")
        }
    }
}

struct ChatPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("AI chat will be available in a future update.")
            )
            .navigationTitle("Chat")
        }
    }
}

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    FeedListView()
                } label: {
                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                }

                NavigationLink {
                    Text("Tags — coming soon")
                } label: {
                    Label("Tags", systemImage: "tag")
                }

                NavigationLink {
                    Text("Settings — coming soon")
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("More")
        }
    }
}
