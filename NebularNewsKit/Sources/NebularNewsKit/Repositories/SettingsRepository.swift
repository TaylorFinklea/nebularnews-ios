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
        if let existing = await get() {
            if existing.normalizeStorageSettings() {
                existing.updatedAt = Date()
                try? modelContext.save()
            }
            return existing
        }
        let settings = AppSettings()
        _ = settings.normalizeStorageSettings()
        modelContext.insert(settings)
        try? modelContext.save()
        return settings
    }

    public func archiveAfterDays() async -> Int {
        max(await getOrCreate().archiveAfterDays, 1)
    }

    public func deleteArchivedAfterDays() async -> Int {
        max(await getOrCreate().deleteArchivedAfterDays, 1)
    }

    public func searchArchivedByDefault() async -> Bool {
        await getOrCreate().searchArchivedByDefault
    }

    public func maxArticlesPerFeed() async -> Int {
        max(await getOrCreate().maxArticlesPerFeed, 1)
    }

    public func pollIntervalMinutes() async -> Int {
        max(await getOrCreate().pollIntervalMinutes, 1)
    }

    public func personalizationRebuildVersion() async -> Int {
        await getOrCreate().personalizationRebuildVersion
    }

    public func setPersonalizationRebuildVersion(_ version: Int) async {
        let settings = await getOrCreate()
        settings.personalizationRebuildVersion = version
        settings.updatedAt = Date()
        try? modelContext.save()
    }
}
