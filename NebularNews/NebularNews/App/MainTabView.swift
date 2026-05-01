import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var companionSavedCount = 0
    @State private var showSettings = false

    /// Opt-in firehose tab. Defaults off — M18's chat-first Today is the
    /// primary surface, but power users can re-enable the raw article list
    /// from Settings → Reading.
    @AppStorage("showArticlesTab") private var showArticlesTab = false

    enum RootSection: String, CaseIterable {
        // M18 dropped 'articles' (the firehose) in favor of the chat-first
        // briefing surface as Today. The case is restored as opt-in so deep
        // links and AI tool calls (`navigate_to_tab`) can still route to it
        // when the user has it enabled.
        case today, discover, articles, library
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
        .onChange(of: appState.pendingTabSwitch) { _, newValue in
            guard let raw = newValue, let target = RootSection(rawValue: raw) else { return }
            selectedTab = target
            appState.pendingTabSwitch = nil
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
                TodayBriefingView()
            case .discover:
                CompanionDiscoverView(showSettings: $showSettings)
            case .articles:
                CompanionArticlesView(showSettings: $showSettings)
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
                TodayBriefingView()
            }

            Tab("Discover", systemImage: "safari") {
                CompanionDiscoverView(showSettings: $showSettings)
            }

            if showArticlesTab {
                Tab("Articles", systemImage: "newspaper") {
                    CompanionArticlesView(showSettings: $showSettings)
                }
            }

            Tab("Library", systemImage: "books.vertical") {
                LibraryView(showSettings: $showSettings)
            }
            .badge(companionSavedCount)
        }
        .tint(.accent)
        // The chat-first Today tab has its own input bar; the floating
        // AI overlay still appears on Discover / Library so users can
        // ask follow-ups while browsing those surfaces.
        .overlay { AIAssistantOverlay() }
    }
    #endif

    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            NavigationLink(value: RootSection.today) {
                Label("Today", systemImage: "sun.max")
            }
            NavigationLink(value: RootSection.discover) {
                Label("Discover", systemImage: "safari")
            }
            if showArticlesTab {
                NavigationLink(value: RootSection.articles) {
                    Label("Articles", systemImage: "newspaper")
                }
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
