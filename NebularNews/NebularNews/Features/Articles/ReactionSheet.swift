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

    private var currentOptions: [ReactionReasonOption] {
        guard let selectedValue else { return [] }
        return reasonOptions(for: selectedValue)
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
                                        .foregroundStyle(.tint)
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
        let previousValue = article.reactionValue
        let newValue = selectedValue
        let canonicalCodes = selectedValue.map {
            canonicalizeReasonCodes(
                for: $0,
                codes: currentOptions
                    .filter { selectedCodes.contains($0.code) }
                    .map(\.code)
            )
        } ?? []

        article.reactionValue = newValue
        article.reactionReasonCodes = canonicalCodes.isEmpty ? nil : canonicalCodes.joined(separator: ",")
        try? modelContext.save()

        Task {
            let service = LocalStandalonePersonalizationService(modelContainer: modelContext.container)
            await service.processReactionChange(
                articleID: article.id,
                previousValue: previousValue,
                newValue: newValue,
                reasonCodes: canonicalCodes
            )
        }
        dismiss()
    }

    private func clearReaction() {
        let previousValue = article.reactionValue
        article.reactionValue = nil
        article.reactionReasonCodes = nil
        try? modelContext.save()

        Task {
            let service = LocalStandalonePersonalizationService(modelContainer: modelContext.container)
            await service.processReactionChange(
                articleID: article.id,
                previousValue: previousValue,
                newValue: nil,
                reasonCodes: []
            )
        }
        dismiss()
    }
}
