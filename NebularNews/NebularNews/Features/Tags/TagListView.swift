import SwiftUI
import NebularNewsKit

/// Manage all tags -- create, view, delete.
///
/// Ported from the standalone-era `TagListView`, now backed by
/// Supabase via `appState.supabase` instead of SwiftData `@Query`.
struct TagListView: View {
    @Environment(AppState.self) private var appState

    @State private var tags: [CompanionTagWithCount] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNewTagAlert = false
    @State private var newTagName = ""

    var body: some View {
        List {
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if tags.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Create tags to categorize your articles.")
                )
            } else {
                ForEach(tags) { tag in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 12, height: 12)

                        Text(tag.name)
                            .font(.body)

                        Spacer()

                        Text("\(tag.articleCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteTags)
            }
        }
        .navigationTitle("Tags")
        .overlay {
            if isLoading && tags.isEmpty {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newTagName = ""
                    showNewTagAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Tag", isPresented: $showNewTagAlert) {
            TextField("Tag name", text: $newTagName)
            Button("Create") { Task { await createTag() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new tag.")
        }
        .refreshable { await loadTags() }
        .task {
            if tags.isEmpty {
                await loadTags()
            }
        }
    }

    private func loadTags() async {
        isLoading = true
        errorMessage = nil
        do {
            tags = try await appState.supabase.fetchTags()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createTag() async {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await appState.supabase.createTag(name: trimmed)
            await loadTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTags(at offsets: IndexSet) {
        let toDelete = offsets.map { tags[$0] }
        Task {
            for tag in toDelete {
                do {
                    try await appState.supabase.deleteTag(id: tag.id)
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
            await loadTags()
        }
    }

    private func tagColor(for tag: CompanionTagWithCount) -> Color {
        if let hex = tag.color {
            return Color(hex: hex)
        }
        return .secondary
    }
}
