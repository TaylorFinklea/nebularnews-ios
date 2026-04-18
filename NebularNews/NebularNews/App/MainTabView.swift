import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var companionSavedCount = 0
    @State private var showSettings = false

    enum RootSection: String, CaseIterable {
        case today, articles, discover, library
    }

    @State private var selectedTab: RootSection? = .today

    var body: some View {
        Group {
            #if os(macOS)
            splitViewBody
            #else
            if horizontalSizeClass == .regular {
                splitViewBody
            } else {
                tabViewBody
            }
            #endif
        }
        .task {
            await loadCompanionSavedCount()
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    private var splitViewBody: some View {
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
            switch selectedTab ?? .today {
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
        #if os(iOS)
        .overlay { AIAssistantOverlay() }
        #endif
    }

    #if os(iOS)
    private var tabViewBody: some View {
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
        .tint(.accent)
        .overlay { AIAssistantOverlay() }
    }
    #endif

    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            NavigationLink(value: RootSection.today) {
                Label("Today", systemImage: "sun.max")
            }
            NavigationLink(value: RootSection.articles) {
                Label("Articles", systemImage: "doc.text")
            }
            NavigationLink(value: RootSection.discover) {
                Label("Discover", systemImage: "safari")
            }
            NavigationLink(value: RootSection.library) {
                Label("Library", systemImage: "books.vertical")
            }
            .badge(companionSavedCount)
        }
        .navigationTitle("Nebular News")
    }

    @ViewBuilder
    private var settingsSheet: some View {
        NavigationStack {
            ProfileView()
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSettings = false }
                    }
                    #else
                    ToolbarItem(placement: .platformTrailing) {
                        Button("Done") { showSettings = false }
                    }
                    #endif
                }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    private func loadCompanionSavedCount() async {
        if let payload = try? await appState.supabase.fetchArticles(limit: 1, saved: true) {
            companionSavedCount = payload.total
        }
    }
}
