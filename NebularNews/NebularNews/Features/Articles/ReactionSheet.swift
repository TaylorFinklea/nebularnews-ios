import SwiftUI
import SwiftData
import os
import NebularNewsKit

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
    category: "ReactionSheet"
)

/// Sheet for reacting to an article with optional reason codes.
struct ReactionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let articleID: String
    let allowsDismiss: Bool

    @Query private var articles: [Article]

    @State private var selectedSelection: ReactionSelection? = nil
    @State private var selectedCodes: Set<String> = []

    init(article: Article, allowsDismiss: Bool = false) {
        let articleID = article.id
        self.articleID = articleID
        self.allowsDismiss = allowsDismiss
        _articles = Query(
            filter: #Predicate<Article> { $0.id == articleID },
            sort: [SortDescriptor(\Article.publishedAt)]
        )
        _selectedSelection = State(initialValue: ReactionSelection(article: article, allowsDismiss: allowsDismiss))
        _selectedCodes = State(
            initialValue: Set(
                article.reactionReasonCodes?
                    .split(separator: ",")
                    .map(String.init) ?? []
            )
        )
    }

    private var article: Article? {
        articles.first
    }

    private var currentOptions: [ReactionReasonOption] {
        guard let selectedValue else { return [] }
        return reasonOptions(for: selectedValue)
    }

    private var selectedValue: Int? {
        selectedSelection?.reactionValue
    }

    private var hasPersistedFeedback: Bool {
        article?.reactionValue != nil || article?.isDismissed == true
    }

    private var selectionBinding: Binding<ReactionSelection?> {
        Binding(
            get: { selectedSelection },
            set: { newValue in
                selectedSelection = newValue
                selectedCodes.removeAll()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Response") {
                    Picker("Feedback", selection: selectionBinding) {
                        Text("Liked it")
                            .tag(ReactionSelection?.some(.liked))

                        if allowsDismiss {
                            Text("Dismiss")
                                .tag(ReactionSelection?.some(.dismissed))
                        }

                        Text("Not for me")
                            .tag(ReactionSelection?.some(.disliked))
                    }
                    .pickerStyle(.inline)
                }

                if selectedSelection == .dismissed {
                    Section {
                        Text("Dismiss keeps this article out of your unread queue without opening it.")
                            .foregroundStyle(.secondary)
                    }
                } else if let _ = selectedValue {
                    Section {
                        ForEach(currentOptions, id: \.code) { option in
                            Button {
                                toggleReasonCode(option.code)
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedCodes.contains(option.code) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Reasons")
                    } footer: {
                        Text("Reasons help Nebular learn why a story matched or missed.")
                    }
                } else {
                    Section {
                        Text(allowsDismiss ? "Select feedback to continue." : "Select a reaction to continue.")
                            .foregroundStyle(.secondary)
                    }
                }

                if hasPersistedFeedback {
                    Section {
                        Button("Clear Feedback", role: .destructive) {
                            clearReaction()
                        }
                    }
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
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleReasonCode(_ code: String) {
        if selectedCodes.contains(code) {
            selectedCodes.remove(code)
        } else {
            selectedCodes.insert(code)
        }
    }

    private func save() {
        guard let article else {
            dismiss()
            return
        }

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
            article.setReaction(value: newValue, reasonCodes: canonicalCodes)
        case .dismissed:
            article.markDismissed()
            article.setReaction(value: nil)
        case .none:
            article.clearDismissal()
            article.setReaction(value: nil)
        }
        saveContext()

        let newDismissedAt = article.dismissedAt

        Task {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            do {
                try await articleRepo.syncStandaloneUserState(id: article.id)
            } catch {
                logger.error("Failed to sync reaction state for \(article.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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
        guard let article else {
            dismiss()
            return
        }

        let previousValue = article.reactionValue
        let previousDismissedAt = article.dismissedAt
        selectedSelection = nil
        selectedCodes.removeAll()
        article.clearDismissal()
        article.setReaction(value: nil)
        saveContext()

        Task {
            let articleRepo = LocalArticleRepository(modelContainer: modelContext.container)
            do {
                try await articleRepo.syncStandaloneUserState(id: article.id)
            } catch {
                logger.error("Failed to sync clear-reaction state for \(article.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save model context: \(error.localizedDescription, privacy: .public)")
        }
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
