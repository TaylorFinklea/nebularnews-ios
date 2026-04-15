import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    @State private var companionSavedCount = 0
    @State private var showSettings = false

    #if os(macOS)
    enum Tab: String, CaseIterable {
        case today, articles, discover, library
    }

    @State private var selectedTab: Tab = .today
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebarContent
            .toolbar {
                ToolbarItem {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        } detail: {
            switch selectedTab {
            case .today:
                CompanionTodayView(showSettings: $showSettings)
            case .articles:
                CompanionArticlesView(showSettings: $showSettings)
            case .discover:
                CompanionDiscoverView(showSettings: $showSettings)
            case .library:
                LibraryView(showSettings: $showSettings)
            }
        }
        .task {
            await loadCompanionSavedCount()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            .frame(minWidth: 500, minHeight: 500)
        }
        #else
        TabView {
            Tab("Today", systemImage: "sun.max") {
                CompanionTodayView(showSettings: $showSettings)
            }

            Tab("Articles", systemImage: "doc.text") {
                CompanionArticlesView(showSettings: $showSettings)
            }

            Tab("Discover", systemImage: "safari") {
                CompanionDiscoverView(showSettings: $showSettings)
            }

            Tab("Library", systemImage: "books.vertical") {
                LibraryView(showSettings: $showSettings)
            }
            .badge(companionSavedCount)
        }
        .task {
            await loadCompanionSavedCount()
        }
        .tint(.accent)
        .overlay { AIAssistantOverlay() }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .platformTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        #endif
    }

    #if os(macOS)
    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            Label("Today", systemImage: "sun.max")
                .tag(Tab.today)
            Label("Articles", systemImage: "doc.text")
                .tag(Tab.articles)
            Label("Discover", systemImage: "safari")
                .tag(Tab.discover)
            Label("Library", systemImage: "books.vertical")
                .tag(Tab.library)
                .badge(companionSavedCount)
        }
        .navigationTitle("Nebular News")
    }
    #endif

    private func loadCompanionSavedCount() async {
        if let payload = try? await appState.supabase.fetchArticles(limit: 1, saved: true) {
            companionSavedCount = payload.total
        }
    }
}
