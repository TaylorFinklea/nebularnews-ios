import SwiftUI
import SwiftData
import NebularNewsKit

/// Sheet for assigning and managing tags on an article.
struct TagPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @Query(sort: [SortDescriptor(\Tag.name)])
    private var allTags: [Tag]
    @Query private var tagSuggestions: [ArticleTagSuggestion]

    @State private var showCreateTagAlert = false
    @State private var newTagName = ""

    init(article: Article) {
        self.article = article
        let articleID = article.id
        _tagSuggestions = Query(
            filter: #Predicate<ArticleTagSuggestion> {
                $0.articleId == articleID && $0.dismissedAt == nil
            },
            sort: [SortDescriptor(\ArticleTagSuggestion.createdAt)]
        )
    }

    private var attachedTags: [Tag] {
        allTags.filter(isAssigned)
    }

    private var availableTags: [Tag] {
        allTags.filter { !isAssigned($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !tagSuggestions.isEmpty {
                    Section {
                        ForEach(tagSuggestions, id: \.id) { suggestion in
                            suggestionRow(suggestion)
                        }
                    } header: {
                        Text("Suggested")
                    } footer: {
                        Text("Suggested tags stay separate until you accept them.")
                    }
                }

                if !attachedTags.isEmpty {
                    Section {
                        ForEach(attachedTags, id: \.id) { tag in
                            tagRow(tag, isAttached: true)
                        }
                    } header: {
                        Text("Attached")
                    }
                }

                Section {
                    if availableTags.isEmpty {
                        Text("No additional tags available yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableTags, id: \.id) { tag in
                            tagRow(tag, isAttached: false)
                        }
                    }
                } header: {
                    Text(attachedTags.isEmpty ? "All Tags" : "Available Tags")
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Tag", systemImage: "plus") {
                        newTagName = ""
                        showCreateTagAlert = true
                    }
                }
            }
            .alert("New Tag", isPresented: $showCreateTagAlert) {
                TextField("Tag name", text: $newTagName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    createAndAssign()
                }
            } message: {
                Text("Create a tag and attach it to this article.")
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: ArticleTagSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.name)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if let confidence = suggestion.confidence {
                    Text("\(Int((confidence * 100).rounded()))% confidence")
                }

                if let sourceProvider = suggestion.sourceProvider, !sourceProvider.isEmpty {
                    Text(sourceProvider.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Accept", systemImage: "checkmark") {
                acceptSuggestion(suggestion)
            }
            .tint(.green)

            Button("Dismiss", systemImage: "xmark", role: .destructive) {
                dismissSuggestion(suggestion)
            }
        }
        .contextMenu {
            Button("Accept", systemImage: "checkmark") {
                acceptSuggestion(suggestion)
            }

            Button("Dismiss", systemImage: "xmark", role: .destructive) {
                dismissSuggestion(suggestion)
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: Tag, isAttached: Bool) -> some View {
        Button {
            toggleTag(tag)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(tagColor(for: tag))
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .foregroundStyle(.primary)

                Spacer()

                if isAttached {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func isAssigned(_ tag: Tag) -> Bool {
        article.tags?.contains(where: { $0.id == tag.id }) ?? false
    }

    private func toggleTag(_ tag: Tag) {
        if isAssigned(tag) {
            article.tags?.removeAll(where: { $0.id == tag.id })
            persistSystemTagIDs(article.systemTagIds.filter { $0 != tag.id })
        } else {
            if article.tags == nil { article.tags = [] }
            article.tags?.append(tag)
        }
        try? modelContext.save()
        rescoreArticle()
    }

    private func createAndAssign() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedName = Tag.normalizeName(trimmed)
        let tag: Tag
        if let existing = allTags.first(where: { $0.nameNormalized == normalizedName }) {
            tag = existing
        } else {
            tag = Tag(
                name: trimmed,
                colorHex: defaultColorHex(for: trimmed),
                slug: Tag.normalizeSlug(trimmed),
                isCanonical: false
            )
            modelContext.insert(tag)
        }

        if article.tags == nil { article.tags = [] }
        if !(article.tags?.contains(where: { $0.id == tag.id }) ?? false) {
            article.tags?.append(tag)
        }
        try? modelContext.save()
        rescoreArticle()
    }

    private func persistSystemTagIDs(_ tagIDs: [String]) {
        var seen: Set<String> = []
        let uniqueTagIDs = tagIDs.filter { seen.insert($0).inserted }
        article.systemTagIdsJson = uniqueTagIDs.isEmpty ? nil : encodedJSON(uniqueTagIDs)
    }

    private func encodedJSON(_ values: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(values) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func rescoreArticle() {
        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            try? await service.rescoreArticle(articleID: article.id)
        }
    }

    private func tagColor(for tag: Tag) -> Color {
        if let hex = tag.colorHex { return Color(hex: hex) }
        return .secondary
    }

    private func defaultColorHex(for name: String) -> String {
        let palette = [
            "7c6aef", "59c7e5", "6bd1ba", "f5ba6b",
            "f47a94", "f2e36b", "6baaff", "a3d977"
        ]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }

    private func acceptSuggestion(_ suggestion: ArticleTagSuggestion) {
        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.acceptTagSuggestion(articleID: article.id, suggestionID: suggestion.id)
        }
    }

    private func dismissSuggestion(_ suggestion: ArticleTagSuggestion) {
        Task {
            let service = LocalStandalonePersonalizationService(
                modelContainer: modelContext.container,
                keychainService: AppConfiguration.shared.keychainService
            )
            await service.dismissTagSuggestion(articleID: article.id, suggestionID: suggestion.id)
        }
    }
}
