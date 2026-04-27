import SwiftUI

/// Modal sheet shown when the user taps Dismiss on a brief bullet.
/// Captures duration + resurface preference, then writes a SwiftData
/// `DismissedTopic` row via the supplied callback.
///
/// Defaults: 3 days, resurface-on-developments ON. Both pulled from
/// the user's earlier framing — "Iraq war stuff for 3 days unless major
/// development."
struct DismissDurationSheet: View {
    let signature: String
    let sourceArticleIds: [String]
    let onConfirm: (_ durationDays: Int, _ allowResurface: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var durationDays: Int = 3
    @State private var allowResurface: Bool = true

    private static let presetDays: [Int] = [1, 3, 7, 14]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(signature)
                        .font(.headline)
                    Text("Hide articles like this from briefs and lists. They can resurface for major developments if you allow it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Duration") {
                    Picker("Days", selection: $durationDays) {
                        ForEach(Self.presetDays, id: \.self) { d in
                            Text("\(d) day\(d == 1 ? "" : "s")").tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Resurface on major developments", isOn: $allowResurface)
                } footer: {
                    Text(allowResurface
                        ? "The AI may include this topic again if an article describes a significant new event, escalation, or resolution."
                        : "Strict suppression — no resurfacing during the dismissal window.")
                }
            }
            .navigationTitle("Suppress topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suppress") {
                        onConfirm(durationDays, allowResurface)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
