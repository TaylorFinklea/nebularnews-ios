import SwiftUI

/// Settings → Advanced
///
/// A small list that surfaces the Sync queue inspector and any future
/// advanced settings. Dead-letter count drives the badge on the parent
/// Settings row; pending-or-dead-letter drives the badge inside this view.
struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState

    private var pendingCount: Int {
        appState.syncManager?.pendingActionCount ?? 0
    }

    private var deadLetterCount: Int {
        appState.syncManager?.deadLetterActionCount ?? 0
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SyncQueueInspectorView()
                } label: {
                    syncQueueRow
                }
            } footer: {
                Text("Shows mutations that are queued to sync or failed and need your attention.")
                    .font(.caption)
            }
        }
        .navigationTitle("Advanced")
        .inlineNavigationBarTitle()
    }

    @ViewBuilder
    private var syncQueueRow: some View {
        HStack {
            // Label with dead-letter icon prefix when relevant
            if deadLetterCount > 0 {
                Label {
                    Text("Sync queue")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Text("Sync queue")
            }

            Spacer()

            // Badge: dead-letter count (red) or pending count (default)
            if deadLetterCount > 0 {
                Text("\(deadLetterCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            } else if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.systemFill), in: Capsule())
            }
        }
    }
}
