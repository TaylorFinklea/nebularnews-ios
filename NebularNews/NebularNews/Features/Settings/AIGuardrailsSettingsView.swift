import SwiftUI

/// Settings → Advanced → AI Guardrails
/// Lists all destructive AI assistant tools with their current confirmation policy.
struct AIGuardrailsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(AIGuardrailsPolicy.governedTools, id: \.self) { tool in
                    NavigationLink(value: tool) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(toolDisplayName(tool))
                                .font(.body)
                            Text(modeDescription(appState.aiGuardrails.mode(for: tool)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("AI Guardrails", systemImage: "shield.lefthalf.filled")
            } footer: {
                Text("Choose how the AI handles each destructive action. Confirm pauses for approval; Undo only runs immediately with a 7-second undo window.")
            }
        }
        .navigationTitle("AI Guardrails")
        .navigationDestination(for: String.self) { tool in
            AIGuardrailsToolDetailView(tool: tool)
        }
    }

    private func toolDisplayName(_ tool: String) -> String {
        switch tool {
        case "unsubscribe_from_feed": return "Unsubscribe from a feed"
        case "mark_articles_read": return "Mark 6+ articles as read"
        case "pause_feed": return "Pause a feed"
        case "set_feed_max_per_day": return "Cap a feed's daily articles"
        case "set_feed_min_score": return "Filter a feed by minimum score"
        default: return tool
        }
    }

    private func modeDescription(_ mode: AIGuardrailsPolicy.Mode) -> String {
        switch mode {
        case .confirm: return "Confirm before running"
        case .undoOnly: return "Run immediately with undo"
        }
    }
}

/// Per-tool detail view with a segmented Confirm / Undo only picker.
struct AIGuardrailsToolDetailView: View {
    @Environment(AppState.self) private var appState
    let tool: String

    private var modeBinding: Binding<AIGuardrailsPolicy.Mode> {
        Binding(
            get: { appState.aiGuardrails.mode(for: tool) },
            set: { appState.aiGuardrails.setMode($0, for: tool) }
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Policy", selection: modeBinding) {
                    Text("Confirm").tag(AIGuardrailsPolicy.Mode.confirm)
                    Text("Undo only").tag(AIGuardrailsPolicy.Mode.undoOnly)
                }
                .pickerStyle(.segmented)
            } footer: {
                footerText
            }
        }
        .navigationTitle(toolDisplayName)
    }

    private var toolDisplayName: String {
        switch tool {
        case "unsubscribe_from_feed": return "Unsubscribe from a feed"
        case "mark_articles_read": return "Mark 6+ articles as read"
        case "pause_feed": return "Pause a feed"
        case "set_feed_max_per_day": return "Cap a feed's daily articles"
        case "set_feed_min_score": return "Filter a feed by minimum score"
        default: return tool
        }
    }

    private var footerText: Text {
        switch modeBinding.wrappedValue {
        case .confirm:
            return Text("The AI will show you exactly what it plans to do and wait for your approval before running this action.")
        case .undoOnly:
            return Text("The AI runs this action immediately, then shows a 7-second undo button near the sparkle icon. You can also undo from inside the chat.")
        }
    }
}
