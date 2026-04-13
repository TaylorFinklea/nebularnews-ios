import SwiftUI

/// Shows a list of past AI assistant conversations.
struct AssistantHistoryView: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator

    var body: some View {
        List {
            if coordinator.recentThreads.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Your AI assistant conversations will appear here.")
                )
            } else {
                ForEach(coordinator.recentThreads) { thread in
                    Button {
                        Task {
                            await coordinator.loadThread(thread.id)
                            coordinator.isSheetPresented = true
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title ?? "Conversation")
                                .font(.headline)
                                .lineLimit(1)
                            if let last = thread.lastMessage {
                                Text(last)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack {
                                Text("\(thread.messageCount) messages")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(formatDate(thread.updatedAt))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Chat History")
        .task { await coordinator.loadHistory() }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
