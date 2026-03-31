import SwiftUI

struct CompanionTagListView: View {
    @Environment(AppState.self) private var appState
    @State private var tags: [CompanionTagWithCount] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var newTagName = ""

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            ForEach(tags) { tag in
                HStack {
                    if let color = tag.color {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 12, height: 12)
                    }
                    Text(tag.name)
                    Spacer()
                    Text("\(tag.articleCount)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .onDelete(perform: deleteTags)
        }
        .navigationTitle("Tags")
        .overlay {
            if isLoading && tags.isEmpty {
                ProgressView()
            } else if tags.isEmpty && error == nil {
                ContentUnavailableView("No Tags", systemImage: "tag", description: Text("Tags will appear here when articles are tagged."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Tag", isPresented: $showAddSheet) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { Task { await addTag() } }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
        .refreshable { await loadTags() }
        .task { await loadTags() }
    }

    private func loadTags() async {
        isLoading = true
        error = nil
        do {
            tags = try await appState.supabase.fetchTags()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !name.isEmpty else { return }
        do {
            _ = try await appState.supabase.createTag(name: name)
            await loadTags()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteTags(at offsets: IndexSet) {
        let toDelete = offsets.map { tags[$0] }
        Task {
            for tag in toDelete {
                do {
                    try await appState.supabase.deleteTag(id: tag.id)
                } catch {
                    self.error = error.localizedDescription
                    return
                }
            }
            await loadTags()
        }
    }
}
