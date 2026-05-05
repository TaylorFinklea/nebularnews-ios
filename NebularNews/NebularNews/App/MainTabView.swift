import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

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
        // Build 37 split Today (brief-only) from Agent (ChatGPT-style
        // multi-conversation chat). The opt-in `articles` firehose is
        // unchanged but no longer the default — Discover hosts it now.
        case today, agent, discover, articles, library
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
        .onChange(of: deepLinkRouter.pendingAgentConversationId) { _, newValue in
            // Switching to the Agent tab on deep-link arrival; the
            // conversation push happens inside AgentConversationsView
            // by reading + clearing the same pending property.
            if newValue != nil { selectedTab = .agent }
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
            case .agent:
                AgentConversationsView()
            case .discover:
                CompanionDiscoverView(showSettings: $showSettings)
            case .articles:
                CompanionArticlesView(showSettings: $showSettings)
            case .library:
                LibraryView(showSettings: $showSettings)
            }
        }
    }

    #if os(iOS)
    private var tabViewBody: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayBriefingView()
            }

            Tab("Agent", systemImage: "sparkles") {
                AgentConversationsView()
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
    }
    #endif

    private var sidebarContent: some View {
        List(selection: $selectedTab) {
            NavigationLink(value: RootSection.today) {
                Label("Today", systemImage: "sun.max")
            }
            NavigationLink(value: RootSection.agent) {
                Label("Agent", systemImage: "sparkles")
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
