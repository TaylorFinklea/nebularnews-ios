import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var companionSavedCount = 0
    @State private var showSettings = false

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            NebularBackdrop()

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

                Tab("Lists", systemImage: "bookmark") {
                    CompanionReadingListView(showSettings: $showSettings)
                }
                .badge(companionSavedCount)
            }
            .task {
                await loadCompanionSavedCount()
            }
        }
        .tint(palette.primary)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                CompanionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
    }

    private func loadCompanionSavedCount() async {
        if let payload = try? await appState.mobileAPI.fetchSavedArticles(limit: 0) {
            companionSavedCount = payload.total
        }
    }
}
