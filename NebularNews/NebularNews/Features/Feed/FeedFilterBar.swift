import SwiftUI

enum FeedFilterMode: String, CaseIterable {
    case unread = "Unread"
    case all = "All"
    case scored = "Scored"
    case read = "Read"
}

/// Native filter controls for the Feed tab.
struct FeedFilterBar: View {
    @Binding var filterMode: FeedFilterMode
    let count: Int

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
        }
    }
}
