import SwiftUI

struct AdminToolCallStats: Codable {
    let windowDays: Int
    let totalCalls: Int
    let serverCalls: Int
    let clientCalls: Int
    let messagesWithTools: Int
    let byTool: [AdminToolUsage]
}

struct AdminToolUsage: Codable, Identifiable {
    let name: String
    let count: Int
    let succeeded: Int
    let failed: Int
    let thrownErrors: Int?
    let loggingGap: Int?
    let successRate: Double?
    let lastAt: Int

    var id: String { name }
}

struct AdminToolCallStatsView: View {
    @State private var stats: AdminToolCallStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if let stats {
                Section("Last \(stats.windowDays) days") {
                    LabeledContent("Total tool calls", value: "\(stats.totalCalls)")
                    LabeledContent("Server-executed", value: "\(stats.serverCalls)")
                    LabeledContent("Client-executed", value: "\(stats.clientCalls)")
                    LabeledContent("Messages with tools", value: "\(stats.messagesWithTools)")
                }

                if stats.byTool.isEmpty {
                    Section("By tool") {
                        Text("No tool calls yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("By tool") {
                        ForEach(stats.byTool) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(tool.name)
                                        .font(.subheadline.monospaced())
                                    Spacer()
                                    Text("\(tool.count)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                HStack(spacing: 8) {
                                    if let rate = tool.successRate {
                                        Text(String(format: "%.0f%% success", rate * 100))
                                            .font(.caption)
                                            .foregroundStyle(rate >= 0.9 ? .green : rate >= 0.5 ? .orange : .red)
                                    }
                                    if tool.failed > 0 {
                                        Text("\(tool.failed) failed")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    if let thrown = tool.thrownErrors, thrown > 0 {
                                        Text("\(thrown) thrown")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    if let gap = tool.loggingGap, gap > 0 {
                                        Text("\(gap) unlogged")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    Spacer()
                                    Text(formatDate(tool.lastAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Tool Calls")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                stats = try await APIClient.shared.request(path: "api/admin/tool-call-stats")
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
