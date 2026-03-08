import SwiftUI
import SwiftData
import NebularNewsKit

/// Discover tab — browse topics and manage feeds.
///
/// Combines topic channels (tags with articles) and feed management
/// into a single exploratory surface.
struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var tags: [Tag]

    @State private var viewModel: FeedListViewModel?

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .discover) {
                ScrollView {
                    VStack(spacing: 20) {
                        if let vm = viewModel {
                            DiscoverTopicGrid(tags: tags)
                            DiscoverFeedSection(viewModel: vm)
                        } else {
                            ProgressView()
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let vm = viewModel {
                        Button {
                            Task { await vm.refreshAllFeeds() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(vm.isPolling)
                    }
                }
            }
            .navigationDestination(for: TopicDestination.self) { topic in
                TopicArticlesView(tagId: topic.id, tagName: topic.name)
            }
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .sheet(isPresented: addSheetBinding) {
                if let vm = viewModel {
                    AddFeedSheet { request in
                        switch request {
                        case .single(let url, let title):
                            return await vm.addSingleFeed(feedUrl: url, title: title)
                        case .opml(let entries):
                            return await vm.importOPMLFeeds(entries)
                        }
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = FeedListViewModel(modelContext: modelContext)
                }
            }
            .task {
                await viewModel?.loadFeeds()
            }
        }
    }

    private var addSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showAddSheet ?? false },
            set: { viewModel?.showAddSheet = $0 }
        )
    }
}
