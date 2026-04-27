import SwiftUI
import SwiftData

/// Settings → AI Assistant → Manage Suppressions.
/// Lists active topic dismissals with their countdown to expiry. Lets the
/// user manually unsuppress a topic so it can resurface in the next brief.
/// Expired rows are auto-cleaned by `DismissedTopicService.cleanup()`, but
/// this view always re-runs cleanup on appear so the list never includes
/// stale entries.
struct ManageSuppressionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: DismissedTopicService?
    @State private var topics: [DismissedTopic] = []

    var body: some View {
        List {
            if topics.isEmpty {
                emptyState
            } else {
                ForEach(topics, id: \.id) { topic in
                    row(topic)
                }
                .onDelete(perform: deleteAt)
            }
        }
        .navigationTitle("Suppressed Topics")
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
        .task {
            if service == nil {
                service = DismissedTopicService(context: modelContext)
            }
            service?.cleanup()
            reload()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No active suppressions")
                .font(.headline)
            Text("Topics you dismiss from the brief will appear here. Each entry shows how long until it can resurface.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func row(_ topic: DismissedTopic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.signature)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 12) {
                Label(remainingLabel(topic), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if topic.allowResurfaceOnDevelopments {
                    Label("Resurface on news", systemImage: "exclamationmark.bubble")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove(topic)
            } label: {
                Label("Unsuppress", systemImage: "eye")
            }
        }
    }

    private func remainingLabel(_ topic: DismissedTopic) -> String {
        let interval = topic.expiresAt.timeIntervalSinceNow
        if interval <= 0 { return "Expiring" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: interval).map { "\($0) left" } ?? "—"
    }

    private func reload() {
        topics = service?.all().filter { $0.expiresAt > Date() } ?? []
    }

    private func deleteAt(_ offsets: IndexSet) {
        for idx in offsets {
            remove(topics[idx])
        }
    }

    private func remove(_ topic: DismissedTopic) {
        service?.remove(id: topic.id)
        reload()
    }
}
