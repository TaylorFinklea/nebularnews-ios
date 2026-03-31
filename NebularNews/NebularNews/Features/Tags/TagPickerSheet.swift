import SwiftUI
import NebularNewsKit

/// Sheet for assigning/removing tags on an article.
///
/// Shows all tags with checkmarks for currently assigned ones.
/// Tap to toggle assignment. Includes inline "Create new tag" option.
///
/// Ported from the standalone-era `TagPickerSheet`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData `@Query`.
struct TagPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let articleId: String
    let currentTags: [CompanionTag]
    let onTagsChanged: ([CompanionTag]) -> Void

    @State private var allTags: [CompanionTagWithCount] = []
    @State private var assignedTagIds: Set<String>
    @State private var showNewTagField = false
    @State private var newTagName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        articleId: String,
        currentTags: [CompanionTag],
        onTagsChanged: @escaping ([CompanionTag]) -> Void
    ) {
        self.articleId = articleId
        self.currentTags = currentTags
        self.onTagsChanged = onTagsChanged
        _assignedTagIds = State(initialValue: Set(currentTags.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                ForEach(allTags) { tag in
                    Button {
                        Task { await toggleTag(tag) }
                    } label: {
                        HStack {
                            if let color = tag.color {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 10, height: 10)
                            }

                            Text(tag.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if assignedTagIds.contains(tag.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
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
                            Task { await createAndAssign() }
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
            .overlay {
                if isLoading && allTags.isEmpty {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadAllTags()
            }
        }
    }

    private func loadAllTags() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allTags = try await appState.supabase.fetchTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleTag(_ tag: CompanionTagWithCount) async {
        errorMessage = nil
        do {
            if assignedTagIds.contains(tag.id) {
                let newTags = try await appState.supabase.removeTag(articleId: articleId, tagId: tag.id)
                assignedTagIds.remove(tag.id)
                onTagsChanged(newTags)
            } else {
                let newTags = try await appState.supabase.addTag(articleId: articleId, name: tag.name)
                assignedTagIds.insert(tag.id)
                onTagsChanged(newTags)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAndAssign() async {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil

        do {
            let newTags = try await appState.supabase.addTag(articleId: articleId, name: trimmed)
            onTagsChanged(newTags)
            // Reload all tags to include the new one
            allTags = try await appState.supabase.fetchTags()
            // Update assigned set
            assignedTagIds = Set(newTags.map(\.id))
            newTagName = ""
            showNewTagField = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
