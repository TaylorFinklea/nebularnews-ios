import Foundation
import SwiftUI
import NebularNewsKit

enum FeedFilterMode: String, CaseIterable {
    case unread = "Unread"
    case all = "All"
    case scored = "Scored"
    case read = "Read"
}

enum FeedSortMode: String, CaseIterable, Hashable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case highestFit = "Highest fit"
    case lowestFit = "Lowest fit"

    var articleSort: ArticleSort {
        switch self {
        case .newest:
            return .newest
        case .oldest:
            return .oldest
        case .highestFit:
            return .scoreDesc
        case .lowestFit:
            return .scoreAsc
        }
    }
}

enum FeedDatePreset: String, CaseIterable, Hashable {
    case anyTime = "Any Time"
    case today = "Today"
    case yesterday = "Yesterday"
    case last3Days = "Last 3 Days"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case custom = "Custom Range"
}

struct FeedDateFilter: Hashable {
    var preset: FeedDatePreset
    var startDate: Date
    var endDate: Date

    init(
        preset: FeedDatePreset = .anyTime,
        startDate: Date = Date(),
        endDate: Date = Date()
    ) {
        self.preset = preset
        self.startDate = startDate
        self.endDate = endDate
        normalizeCustomRange()
    }

    var isActive: Bool {
        preset != .anyTime
    }

    mutating func normalizeCustomRange() {
        if startDate > endDate {
            endDate = startDate
        }
    }

    func resolvedBounds(calendar: Calendar = .current, referenceDate: Date = Date()) -> (start: Date?, end: Date?) {
        func endOfDay(for date: Date) -> Date {
            let start = calendar.startOfDay(for: date)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
        }

        switch preset {
        case .anyTime:
            return (nil, nil)
        case .today:
            let start = calendar.startOfDay(for: referenceDate)
            return (start, endOfDay(for: referenceDate))
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            let start = calendar.startOfDay(for: yesterday)
            return (start, endOfDay(for: yesterday))
        case .last3Days:
            let startOfToday = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: -2, to: startOfToday) ?? startOfToday
            return (start, endOfDay(for: referenceDate))
        case .last7Days:
            let startOfToday = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return (start, endOfDay(for: referenceDate))
        case .last30Days:
            let startOfToday = calendar.startOfDay(for: referenceDate)
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return (start, endOfDay(for: referenceDate))
        case .custom:
            let start = calendar.startOfDay(for: startDate)
            return (start, endOfDay(for: endDate))
        }
    }

    func summaryText(calendar: Calendar = .current, referenceDate: Date = Date()) -> String? {
        switch preset {
        case .anyTime:
            return nil
        case .today, .yesterday, .last3Days, .last7Days, .last30Days:
            return preset.rawValue
        case .custom:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("MMM d")

            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            if calendar.isDate(start, inSameDayAs: end) {
                return formatter.string(from: start)
            }
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
    }
}

struct FeedAdvancedFilterState: Hashable {
    var dateFilter = FeedDateFilter()
    var sortMode: FeedSortMode = .newest
    var storageScopeOverride: ArticleStorageScope?

    var isActive: Bool {
        dateFilter.isActive || sortMode != .newest || storageScopeOverride != nil
    }

    var articleSort: ArticleSort {
        sortMode.articleSort
    }

    mutating func clear(referenceDate: Date = Date()) {
        dateFilter = FeedDateFilter(startDate: referenceDate, endDate: referenceDate)
        sortMode = .newest
        storageScopeOverride = nil
    }

    func effectiveStorageScope(
        searchText: String,
        searchArchivedByDefault: Bool
    ) -> ArticleStorageScope {
        if let storageScopeOverride {
            return storageScopeOverride
        }

        if searchArchivedByDefault,
           !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .all
        }

        return .active
    }

    func apply(
        to filter: inout ArticleFilter,
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        searchText: String = "",
        searchArchivedByDefault: Bool = false
    ) {
        let bounds = dateFilter.resolvedBounds(calendar: calendar, referenceDate: referenceDate)
        filter.publishedAfter = bounds.start
        filter.publishedBefore = bounds.end
        filter.storageScope = effectiveStorageScope(
            searchText: searchText,
            searchArchivedByDefault: searchArchivedByDefault
        )
    }

    func summaryText(
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        searchText: String = "",
        searchArchivedByDefault: Bool = false
    ) -> String? {
        var parts = [dateFilter.summaryText(calendar: calendar, referenceDate: referenceDate)]
        if sortMode != .newest {
            parts.append(sortMode.rawValue)
        }

        let scope = effectiveStorageScope(
            searchText: searchText,
            searchArchivedByDefault: searchArchivedByDefault
        )
        if storageScopeOverride != nil {
            parts.append(scope.feedFilterLabel)
        }

        let activeParts = parts.compactMap { $0 }
        guard !activeParts.isEmpty else {
            return nil
        }
        return activeParts.joined(separator: " · ")
    }
}

/// Native filter controls for the Feed tab.
struct FeedFilterBar: View {
    @Binding var filterMode: FeedFilterMode
    let count: Int
    let activeSummary: String?
    let onClearAdvancedFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Filter", selection: $filterMode) {
                ForEach(FeedFilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            LabeledContent("Visible", value: "\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let activeSummary {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(activeSummary, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Button("Clear", action: onClearAdvancedFilters)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

struct FeedAdvancedFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let quickFilterMode: FeedFilterMode
    let searchText: String
    let searchArchivedByDefault: Bool
    let onApply: (FeedAdvancedFilterState) -> Void

    @State private var draft: FeedAdvancedFilterState

    init(
        state: FeedAdvancedFilterState,
        quickFilterMode: FeedFilterMode,
        searchText: String,
        searchArchivedByDefault: Bool,
        onApply: @escaping (FeedAdvancedFilterState) -> Void
    ) {
        self.quickFilterMode = quickFilterMode
        self.searchText = searchText
        self.searchArchivedByDefault = searchArchivedByDefault
        self.onApply = onApply
        _draft = State(initialValue: state)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Narrow the feed by date and sort order to find older stories faster.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Date") {
                    Picker("Range", selection: $draft.dateFilter.preset) {
                        ForEach(FeedDatePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue)
                                .tag(preset)
                        }
                    }

                    if draft.dateFilter.preset == .custom {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { draft.dateFilter.startDate },
                                set: { newValue in
                                    draft.dateFilter.startDate = newValue
                                    draft.dateFilter.normalizeCustomRange()
                                }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)

                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { draft.dateFilter.endDate },
                                set: { newValue in
                                    draft.dateFilter.endDate = newValue
                                    draft.dateFilter.normalizeCustomRange()
                                }
                            ),
                            in: draft.dateFilter.startDate...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                }

                Section("Sort") {
                    Picker("Order", selection: $draft.sortMode) {
                        ForEach(FeedSortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                }

                Section("Scope") {
                    Picker(
                        "Articles",
                        selection: Binding(
                            get: {
                                draft.effectiveStorageScope(
                                    searchText: searchText,
                                    searchArchivedByDefault: searchArchivedByDefault
                                )
                            },
                            set: { newValue in
                                draft.storageScopeOverride = newValue
                            }
                        )
                    ) {
                        ForEach(ArticleStorageScope.allCases, id: \.self) { scope in
                            Text(scope.feedFilterLabel)
                                .tag(scope)
                        }
                    }
                }

                Section("Match") {
                    LabeledContent("Status", value: quickFilterMode.rawValue)

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        LabeledContent("Search", value: "Any text")
                    } else {
                        LabeledContent("Search", value: searchText)
                    }
                }

                Section {
                    Button("Clear Filters", role: .destructive) {
                        draft.clear()
                    }
                    .disabled(!draft.isActive)
                }
            }
            .navigationTitle("Filter Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension ArticleStorageScope {
    var feedFilterLabel: String {
        switch self {
        case .active:
            return "Current"
        case .archived:
            return "Archived"
        case .all:
            return "All"
        }
    }
}
