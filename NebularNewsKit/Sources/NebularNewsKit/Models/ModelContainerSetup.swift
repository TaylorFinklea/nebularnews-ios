import Foundation
import SwiftData

/// All SwiftData model types registered with the container.
public let allModelTypes: [any PersistentModel.Type] = [
    Feed.self,
    Article.self,
    ArticleProcessingJob.self,
    TodaySnapshot.self,
    Tag.self,
    SignalWeight.self,
    TopicAffinity.self,
    AuthorAffinity.self,
    FeedAffinity.self,
    ArticleTagSuggestion.self,
    ChatThread.self,
    ChatMessage.self,
    AppSettings.self
]

/// Creates a `ModelContainer`.
///
/// CloudKit sync is optional and disabled by default so the project can build
/// and run without a personal iCloud container.
public func makeModelContainer(
    cloudKitEnabled: Bool = false,
    cloudKitContainerIdentifier: String? = nil
) throws -> ModelContainer {
    let schema = Schema(allModelTypes)
    let config = ModelConfiguration(
        cloudKitContainerIdentifier,
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: cloudKitEnabled ? .automatic : .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a `ModelContainer` without iCloud sync (for testing/previews).
public func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema(allModelTypes)
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}
