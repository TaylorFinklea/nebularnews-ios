import Foundation
import Observation
import SwiftData
import NebularNewsKit

@Observable
@MainActor
final class FeedListViewModel {
    private let feedRepo: LocalFeedRepository

    var feeds: [Feed] = []
    var isLoading = false
    var showAddSheet = false
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.feedRepo = LocalFeedRepository(modelContainer: modelContext.container)
    }

    func loadFeeds() async {
        isLoading = true
        feeds = await feedRepo.list()
        isLoading = false
    }

    func deleteFeed(_ feed: Feed) async {
        do {
            try await feedRepo.delete(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
        }
    }

    func toggleEnabled(_ feed: Feed) async {
        do {
            try await feedRepo.setEnabled(id: feed.id, enabled: !feed.isEnabled)
            await loadFeeds()
        } catch {
            errorMessage = "Failed to update feed: \(error.localizedDescription)"
        }
    }
}
