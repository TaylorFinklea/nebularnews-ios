import SwiftUI
import SwiftData
import NebularNewsKit

/// Manage all tags — create, view, delete.
struct TagListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Tag.name)])
    private var tags: [Tag]

    @State private var showNewTagAlert = false
    @State private var newTagName = ""

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Create tags to categorize your articles.")
                )
            } else {
                ForEach(tags, id: \.id) { tag in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 12, height: 12)

                        Text(tag.name)
                            .font(.body)

                        Spacer()

                        Text("\(tag.articles?.count ?? 0)")
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
            Button("Create") { createTag() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new tag.")
        }
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedName = Tag.normalizeName(trimmed)
        guard !tags.contains(where: { $0.nameNormalized == normalizedName }) else { return }

        let tag = Tag(
            name: trimmed,
            colorHex: defaultColorHex(for: trimmed),
            slug: Tag.normalizeSlug(trimmed),
            isCanonical: false
        )
        modelContext.insert(tag)
        try? modelContext.save()
    }

    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
        try? modelContext.save()
    }

    private func tagColor(for tag: Tag) -> Color {
        if let hex = tag.colorHex {
            return Color(hex: hex)
        }
        return .secondary
    }

    /// Assigns a default color from a palette based on the tag name's hash.
    /// This gives each tag a visually distinct color without user input.
    private func defaultColorHex(for name: String) -> String {
        let palette = [
            "7c6aef", // purple
            "59c7e5", // cyan
            "6bd1ba", // teal
            "f5ba6b", // orange
            "f47a94", // pink
            "f2e36b", // yellow
            "6baaff", // blue
            "a3d977", // green
        ]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }
}
