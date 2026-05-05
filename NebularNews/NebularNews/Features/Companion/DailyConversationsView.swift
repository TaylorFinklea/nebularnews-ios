import SwiftUI

/// List of every day the user had chat activity in the assistant
/// thread, newest first. Each row links to a read-only day view.
/// Replaces the legacy BriefHistoryView surface from the Today
/// toolbar; the brief is now part of the conversation rather than a
/// standalone artifact, so the history UI groups by day.
struct DailyConversationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var days: [CompanionConversationDay] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if days.isEmpty && !isLoading {
                    emptyStateSection
                } else {
                    ForEach(grouped(), id: \.0) { header, rows in
                        Section(header: Text(header)) {
                            ForEach(rows) { day in
                                NavigationLink(destination: DayConversationView(day: day)) {
                                    row(for: day)
                                }
                            }
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await reload() }
            .task { if days.isEmpty { await reload() } }
            .overlay {
                if isLoading && days.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No conversations yet")
                    .font(.headline)
                Text("Once you have a brief or chat on a day, it shows up here so you can scroll back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private func row(for day: CompanionConversationDay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: day.hasBrief ? "sparkles" : "bubble.left.and.text.bubble.right")
                .font(.title3)
                .foregroundStyle(day.hasBrief ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayLabel(for: day.day))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                if let preview = day.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(day.messageCount) message\(day.messageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Grouping

    /// "This week" buckets the last 7 local days; older days roll up
    /// into MMMM yyyy month groups so the list stays scannable as the
    /// user accumulates a long history.
    private func grouped() -> [(String, [CompanionConversationDay])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var thisWeek: [CompanionConversationDay] = []
        var older: [(String, [CompanionConversationDay])] = []
        var current: (String, [CompanionConversationDay])?

        for day in days {
            guard let date = parseDay(day.day) else { continue }
            if let cutoff = sevenDaysAgo, date >= cutoff {
                thisWeek.append(day)
            } else {
                let label = formatter.string(from: date)
                if current?.0 == label {
                    current!.1.append(day)
                } else {
                    if let c = current { older.append(c) }
                    current = (label, [day])
                }
            }
        }
        if let c = current { older.append(c) }

        var result: [(String, [CompanionConversationDay])] = []
        if !thisWeek.isEmpty {
            result.append(("This week", thisWeek))
        }
        result.append(contentsOf: older)
        return result
    }

    // MARK: - Formatting

    private func displayLabel(for dayString: String) -> String {
        guard let date = parseDay(dayString) else { return dayString }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let day = calendar.startOfDay(for: date)
        if day == today { return "Today" }
        if day == yesterday { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private func parseDay(_ dayString: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: dayString)
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            days = try await appState.supabase.fetchConversationDays()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
