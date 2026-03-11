import Foundation
import SwiftData

/// All SwiftData model types registered with the container.
public let cloudSyncedModelTypes: [any PersistentModel.Type] = [
    Feed.self,
    Article.self,
    Tag.self,
    ChatThread.self,
    ChatMessage.self,
    AppSettings.self
]

/// Models that stay local even when CloudKit is enabled.
///
/// These entities are operational/read-model data or use features that
/// Core Data with CloudKit does not support, such as uniqueness constraints.
public let localOnlyModelTypes: [any PersistentModel.Type] = [
    ArticleProcessingJob.self,
    TodaySnapshot.self,
    SignalWeight.self,
    TopicAffinity.self,
    AuthorAffinity.self,
    FeedAffinity.self,
    ArticleTagSuggestion.self
]

public let allModelTypes: [any PersistentModel.Type] = cloudSyncedModelTypes + localOnlyModelTypes

/// Creates a `ModelContainer`.
///
/// CloudKit sync is optional and disabled by default so the project can build
/// and run without a personal iCloud container.
public func makeModelContainer(
    cloudKitEnabled: Bool = false,
    cloudKitContainerIdentifier: String? = nil
) throws -> ModelContainer {
    let fullSchema = Schema(allModelTypes)
    let cloudSchema = Schema(cloudSyncedModelTypes)
    let localSchema = Schema(localOnlyModelTypes)
    let shouldUseCloudKit = cloudKitEnabled
        && !(cloudKitContainerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

    if shouldUseCloudKit {
        let cloudConfig = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .automatic
        )
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: fullSchema, configurations: [cloudConfig, localConfig])
    }

    let localConfig = ModelConfiguration(
        "Local",
        schema: fullSchema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: fullSchema, configurations: [localConfig])
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
