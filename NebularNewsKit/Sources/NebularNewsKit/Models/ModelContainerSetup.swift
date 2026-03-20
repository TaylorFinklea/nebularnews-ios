import Foundation
import SwiftData

public let allModelTypes: [any PersistentModel.Type] = [
    Feed.self,
    Article.self,
    Tag.self,
    ChatThread.self,
    ChatMessage.self,
    AppSettings.self,
    ArticleProcessingJob.self,
    TodaySnapshot.self,
    SignalWeight.self,
    TopicAffinity.self,
    AuthorAffinity.self,
    FeedAffinity.self,
    ArticleTagSuggestion.self
]

public func makeModelContainer(
    cloudKitEnabled: Bool = false,
    cloudKitContainerIdentifier: String? = nil
) throws -> ModelContainer {
    let schema = Schema(allModelTypes)
    let config = ModelConfiguration(
        "Local",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}

public func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema(allModelTypes)
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
}
