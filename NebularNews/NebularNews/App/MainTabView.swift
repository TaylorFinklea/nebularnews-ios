import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    @State private var companionSavedCount = 0
    @State private var showSettings = false

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                DashboardView()
            }

            Tab("Articles", systemImage: "doc.text") {
                ArticleListView()
            }

            Tab("Discover", systemImage: "safari") {
                CompanionDiscoverView(showSettings: $showSettings)
            }

            Tab("Lists", systemImage: "bookmark") {
                CompanionReadingListView(showSettings: $showSettings)
            }
            .badge(companionSavedCount)
        }
        .task {
            await loadCompanionSavedCount()
        }
        .tint(.accent)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
    }

    private func loadCompanionSavedCount() async {
        if let payload = try? await appState.supabase.fetchArticles(limit: 1, saved: true) {
            companionSavedCount = payload.total
        }
    }
}
