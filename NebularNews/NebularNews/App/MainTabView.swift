import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var companionSavedCount = 0

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            NebularBackdrop()

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
        .tint(palette.primary)
    }

    private func loadCompanionSavedCount() async {
        if let payload = try? await appState.mobileAPI.fetchSavedArticles(limit: 0) {
            companionSavedCount = payload.total
        }
    }
}
