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
    let allowsDismiss: Bool

    @State private var selectedSelection: ReactionSelection? = nil
    @State private var selectedCodes: Set<String> = []

    init(article: Article, allowsDismiss: Bool = false) {
        self.article = article
        self.allowsDismiss = allowsDismiss
        _selectedSelection = State(initialValue: ReactionSelection(article: article, allowsDismiss: allowsDismiss))
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

    private var selectedValue: Int? {
        selectedSelection?.reactionValue
    }

    private var hasPersistedFeedback: Bool {
        article.reactionValue != nil || article.isDismissed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: allowsDismiss ? 24 : 40) {
                    reactionButton(
                        selection: .liked,
                        icon: "hand.thumbsup",
                        filledIcon: "hand.thumbsup.fill",
                        color: .green,
                        label: "Liked it"
                    )

                    if allowsDismiss {
                        reactionButton(
                            selection: .dismissed,
                            icon: "eye.slash",
                            filledIcon: "eye.slash.fill",
                            color: .orange,
                            label: "Dismiss"
                        )
                    }

                    reactionButton(
                        selection: .disliked,
                        icon: "hand.thumbsdown",
                        filledIcon: "hand.thumbsdown.fill",
                        color: .red,
                        label: "Not for me"
                    )
                }
                .padding(.top, 20)

                if selectedSelection == .dismissed {
                    Spacer()
                    Text("Dismiss keeps this article out of your unread queue without opening it.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    Spacer()
                } else if let _ = selectedValue {
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
                    Text(allowsDismiss ? "Select feedback above" : "Select a reaction above")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .navigationTitle(allowsDismiss ? "Feedback" : "Reaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedSelection == nil)
                }
                if hasPersistedFeedback {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear Feedback", role: .destructive) { clearReaction() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Components

    private func reactionButton(
        selection: ReactionSelection,
        icon: String,
        filledIcon: String,
        color: Color,
        label: String
    ) -> some View {
        Button {
            if selectedSelection == selection {
                selectedSelection = nil
                selectedCodes.removeAll()
            } else {
                selectedSelection = selection
                if selection == .dismissed {
                    selectedCodes.removeAll()
                } else {
                    selectedCodes.removeAll()
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedSelection == selection ? filledIcon : icon)
                    .font(.largeTitle)
                    .foregroundStyle(selectedSelection == selection ? color : .secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(selectedSelection == selection ? color : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func save() {
        let previousValue = article.reactionValue
        let previousDismissedAt = article.dismissedAt
        let newValue = selectedValue
        let canonicalCodes = selectedValue.map {
            canonicalizeReasonCodes(
                for: $0,
                codes: currentOptions
                    .filter { selectedCodes.contains($0.code) }
                    .map(\.code)
            )
        } ?? []

        switch selectedSelection {
        case .liked, .disliked:
            article.clearDismissal()
            article.reactionValue = newValue
            article.reactionReasonCodes = canonicalCodes.isEmpty ? nil : canonicalCodes.joined(separator: ",")
        case .dismissed:
            article.markDismissed()
            article.reactionValue = nil
            article.reactionReasonCodes = nil
        case .none:
            article.clearDismissal()
            article.reactionValue = nil
            article.reactionReasonCodes = nil
        }
        try? modelContext.save()

        let newDismissedAt = article.dismissedAt

        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.processReactionChange(
                articleID: article.id,
                previousValue: previousValue,
                newValue: article.reactionValue,
                reasonCodes: canonicalCodes
            )
            await service.processDismissChange(
                articleID: article.id,
                previousDismissedAt: previousDismissedAt,
                newDismissedAt: newDismissedAt
            )
        }
        dismiss()
    }

    private func clearReaction() {
        let previousValue = article.reactionValue
        let previousDismissedAt = article.dismissedAt
        selectedSelection = nil
        selectedCodes.removeAll()
        article.clearDismissal()
        article.reactionValue = nil
        article.reactionReasonCodes = nil
        try? modelContext.save()

        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.processReactionChange(
                articleID: article.id,
                previousValue: previousValue,
                newValue: nil,
                reasonCodes: []
            )
            await service.processDismissChange(
                articleID: article.id,
                previousDismissedAt: previousDismissedAt,
                newDismissedAt: article.dismissedAt
            )
        }
        dismiss()
    }
}

private enum ReactionSelection: Hashable {
    case liked
    case dismissed
    case disliked

    init?(article: Article, allowsDismiss: Bool) {
        if allowsDismiss, article.isDismissed {
            self = .dismissed
            return
        }

        switch article.reactionValue {
        case 1:
            self = .liked
        case -1:
            self = .disliked
        default:
            return nil
        }
    }

    var reactionValue: Int? {
        switch self {
        case .liked:
            return 1
        case .dismissed:
            return nil
        case .disliked:
            return -1
        }
    }
}
