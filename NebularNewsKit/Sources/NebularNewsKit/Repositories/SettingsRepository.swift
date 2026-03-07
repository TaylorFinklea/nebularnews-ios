import Foundation
import SwiftData

/// Simple `ModelActor` for reading `AppSettings` from any isolation context.
///
/// Settings are a singleton — there's at most one `AppSettings` record.
/// This actor provides a safe way to fetch settings from background tasks
/// and the AI enrichment pipeline without touching the main thread.
@ModelActor
public actor LocalSettingsRepository {

    /// Fetch the singleton AppSettings, or nil if none exists yet.
    public func get() async -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Fetch the singleton, creating one with defaults if it doesn't exist.
    public func getOrCreate() async -> AppSettings {
        if let existing = await get() { return existing }
        let settings = AppSettings()
        modelContext.insert(settings)
        try? modelContext.save()
        return settings
    }
}
