import SwiftUI

/// Paginated list of prior news briefs. Presented as a sheet from the Today
/// toolbar. Rows push into BriefDetailView.
struct BriefHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var briefs: [CompanionBriefSummary] = []
    @State private var nextBefore: Int?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var seenIds: Set<String> = SeenBriefStore.load()

    var body: some View {
        NavigationStack {
            List {
                if briefs.isEmpty && !isLoading {
                    emptyStateSection
                } else {
                    ForEach(groupedByDay(), id: \.0) { header, rows in
                        Section(header: Text(header)) {
                            ForEach(rows) { brief in
                                NavigationLink(destination: BriefDetailView(briefId: brief.id)) {
                                    row(brief: brief)
                                }
                            }
                        }
                    }
                    if nextBefore != nil {
                        loadMoreRow
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Briefs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .onAppear { seenIds = SeenBriefStore.load() }
            .overlay {
                if isLoading && briefs.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No briefs yet")
                    .font(.headline)
                Text("Briefs you generate or that arrive at your scheduled times will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private func row(brief: CompanionBriefSummary) -> some View {
        let isUnread = !seenIds.contains(brief.id)
        return HStack(alignment: .top, spacing: 10) {
            // Unread dot — 6pt leading-edge indicator, reserves space even when read so
            // rows don't jump when state flips.
            Circle()
                .fill(isUnread ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.top, 8)
            Image(systemName: iconName(for: brief.editionKind))
                .font(.title3)
                .foregroundStyle(iconColor(for: brief.editionKind))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(kindLabel(brief.editionKind))
                        .font(.subheadline.weight(isUnread ? .bold : .semibold))
                    Spacer()
                    Text(timeLabel(brief.generatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let first = brief.bullets.first {
                    Text(first.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let topic = brief.topicTagName {
                        Text("#\(topic)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Text("\(brief.bullets.count) bullet\(brief.bullets.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
            } else {
                Button("Load older") {
                    Task { await loadMore() }
                }
                .font(.caption)
            }
            Spacer()
        }
        .task { await loadMore() }   // auto-fire on appear
    }

    // MARK: - Grouping

    private func groupedByDay() -> [(String, [CompanionBriefSummary])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        var buckets: [(String, [CompanionBriefSummary])] = []
        var current: (String, [CompanionBriefSummary])?

        for brief in briefs {
            let date = Date(timeIntervalSince1970: TimeInterval(brief.generatedAt) / 1000)
            let day = calendar.startOfDay(for: date)
            let label: String
            if day == today {
                label = "Today"
            } else if day == yesterday {
                label = "Yesterday"
            } else {
                label = formatter.string(from: day)
            }

            if current?.0 == label {
                current!.1.append(brief)
            } else {
                if let c = current { buckets.append(c) }
                current = (label, [brief])
            }
        }
        if let c = current { buckets.append(c) }
        return buckets
    }

    // MARK: - Labels

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "morning": return "Morning Brief"
        case "evening": return "Evening Brief"
        default: return "News Brief"
        }
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "morning": return "sunrise.fill"
        case "evening": return "moon.stars.fill"
        default: return "sparkles"
        }
    }

    private func iconColor(for kind: String) -> Color {
        switch kind {
        case "morning": return .orange
        case "evening": return .indigo
        default: return .purple
        }
    }

    private func timeLabel(_ generatedAt: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(generatedAt) / 1000)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.supabase.fetchBriefHistory(before: nil, limit: 20)
            briefs = payload.briefs
            nextBefore = payload.nextBefore
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let before = nextBefore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let payload = try await appState.supabase.fetchBriefHistory(before: before, limit: 20)
            // De-dupe by id in case of overlap.
            let existing = Set(briefs.map(\.id))
            briefs.append(contentsOf: payload.briefs.filter { !existing.contains($0.id) })
            nextBefore = payload.nextBefore
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
