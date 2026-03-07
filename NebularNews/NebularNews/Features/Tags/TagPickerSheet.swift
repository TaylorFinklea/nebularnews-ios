import SwiftUI
import SwiftData
import NebularNewsKit

/// Sheet for assigning/removing tags on an article.
///
/// Shows all tags with checkmarks for currently assigned ones.
/// Tap to toggle assignment. Includes inline "Create new tag" option.
struct TagPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @Query(sort: [SortDescriptor(\Tag.name)])
    private var allTags: [Tag]

    @State private var showNewTagField = false
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(allTags, id: \.id) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        HStack {
                            Circle()
                                .fill(tagColor(for: tag))
                                .frame(width: 10, height: 10)

                            Text(tag.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isAssigned(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                // Create new tag inline
                if showNewTagField {
                    HStack {
                        TextField("New tag name", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            createAndAssign()
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Button {
                        showNewTagField = true
                    } label: {
                        Label("Create New Tag", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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

        newTagName = ""
        showNewTagField = false
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
            let service = LocalStandalonePersonalizationService(modelContainer: modelContext.container)
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
}
