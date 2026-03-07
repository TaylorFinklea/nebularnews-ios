import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            NebularBackdrop()

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
                        StandaloneDashboardView()
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
        .tint(palette.primary)
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
            NebularScreen {
                List {
                    Section {
                        NavigationLink {
                            FeedListView()
                        } label: {
                            MoreDestinationRow(
                                title: "Feeds",
                                subtitle: "Manage sources, import OPML, and control polling.",
                                systemImage: "antenna.radiowaves.left.and.right",
                                accent: .cyan
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        NavigationLink {
                            TagListView()
                        } label: {
                            MoreDestinationRow(
                                title: "Tags",
                                subtitle: "Review your manual and system tag taxonomy.",
                                systemImage: "tag",
                                accent: .orange
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            MoreDestinationRow(
                                title: "Settings",
                                subtitle: "Tune appearance, polling, and provider behavior.",
                                systemImage: "gear",
                                accent: .purple
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Workspace")
                            .textCase(nil)
                            .font(.caption.weight(.semibold))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("More")
        }
    }
}

private struct MoreDestinationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        GlassCard(style: .raised, tintColor: accent) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
