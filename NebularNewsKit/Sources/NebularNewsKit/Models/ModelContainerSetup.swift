import Foundation
import SwiftData

/// All SwiftData model types registered with the container.
public let allModelTypes: [any PersistentModel.Type] = [
    Feed.self,
    Article.self,
    Tag.self,
    ChatThread.self,
    ChatMessage.self,
    AppSettings.self
]

/// Creates a `ModelContainer` with iCloud sync enabled.
///
/// CloudKit sync requires:
/// - iCloud capability with a CloudKit container in the Xcode project
/// - Remote Notifications in Background Modes
/// - All @Model properties have defaults or are optional
public func makeModelContainer() throws -> ModelContainer {
    let schema = Schema(allModelTypes)
    let config = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .automatic
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
