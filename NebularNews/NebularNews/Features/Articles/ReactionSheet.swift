import SwiftUI
import SwiftData
import NebularNewsKit

/// Sheet for reacting to an article (thumbs up/down with optional reason codes).
///
/// Saves reactions directly to SwiftData (standalone mode), unlike the companion
/// version which posts to the server API.
struct ReactionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @State private var selectedValue: Int? = nil
    @State private var selectedCodes: Set<String> = []

    init(article: Article) {
        self.article = article
        _selectedValue = State(initialValue: article.reactionValue)
        _selectedCodes = State(
            initialValue: Set(
                article.reactionReasonCodes?
                    .split(separator: ",")
                    .map(String.init) ?? []
            )
        )
    }

    private var currentOptions: [ReasonOption] {
        selectedValue == 1 ? Self.upReasons : Self.downReasons
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Thumbs selection
                HStack(spacing: 40) {
                    reactionButton(value: 1, icon: "hand.thumbsup", filledIcon: "hand.thumbsup.fill", color: .green, label: "Liked it")
                    reactionButton(value: -1, icon: "hand.thumbsdown", filledIcon: "hand.thumbsdown.fill", color: .red, label: "Not for me")
                }
                .padding(.top, 20)

                // Reason codes (shown after selecting thumbs)
                if let _ = selectedValue {
                    List(currentOptions, id: \.code) { option in
                        Button {
                            if selectedCodes.contains(option.code) {
                                selectedCodes.remove(option.code)
                            } else {
                                selectedCodes.insert(option.code)
                            }
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                if selectedCodes.contains(option.code) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                    Text("Select a reaction above")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedValue == nil)
                }
                if article.reactionValue != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear Reaction", role: .destructive) { clearReaction() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Components

    private func reactionButton(value: Int, icon: String, filledIcon: String, color: Color, label: String) -> some View {
        Button {
            if selectedValue == value {
                selectedValue = nil
                selectedCodes.removeAll()
            } else {
                selectedValue = value
                selectedCodes.removeAll()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedValue == value ? filledIcon : icon)
                    .font(.largeTitle)
                    .foregroundStyle(selectedValue == value ? color : .secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(selectedValue == value ? color : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func save() {
        article.reactionValue = selectedValue
        let codes = currentOptions
            .filter { selectedCodes.contains($0.code) }
            .map(\.code)
        article.reactionReasonCodes = codes.isEmpty ? nil : codes.joined(separator: ",")
        try? modelContext.save()
        dismiss()
    }

    private func clearReaction() {
        article.reactionValue = nil
        article.reactionReasonCodes = nil
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Reason Options

    private struct ReasonOption {
        let code: String
        let label: String
    }

    private static let upReasons: [ReasonOption] = [
        .init(code: "up_interest_match", label: "Matches my interests"),
        .init(code: "up_source_trust", label: "Trust this source"),
        .init(code: "up_good_timing", label: "Good timing"),
        .init(code: "up_good_depth", label: "Good depth"),
        .init(code: "up_author_like", label: "Like this author"),
    ]

    private static let downReasons: [ReasonOption] = [
        .init(code: "down_off_topic", label: "Off topic for me"),
        .init(code: "down_source_distrust", label: "Don't trust this source"),
        .init(code: "down_stale", label: "Too old / stale"),
        .init(code: "down_too_shallow", label: "Too shallow"),
        .init(code: "down_avoid_author", label: "Avoid this author"),
    ]
}
