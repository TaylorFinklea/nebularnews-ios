import SwiftUI

struct AddToCollectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let articleId: String

    @State private var collections: [CompanionCollection] = []
    @State private var memberOf: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .listRowBackground(Color.clear)
                }

                if !isLoading && collections.isEmpty {
                    ContentUnavailableView(
                        "No collections",
                        systemImage: "folder",
                        description: Text("Create a collection first.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(collections) { collection in
                    Button {
                        Task { await toggleMembership(collection) }
                    } label: {
                        HStack {
                            Image(systemName: collection.icon ?? "folder")
                                .foregroundStyle(Color(hex: collection.color ?? "#007AFF"))
                                .frame(width: 28)

                            Text(collection.name)

                            Spacer()

                            if memberOf.contains(collection.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .tint(.primary)
                }

                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .navigationTitle("Add to Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadData() }
            .sheet(isPresented: $showCreateSheet) {
                CreateCollectionSheet { newCollection in
                    collections.append(newCollection)
                    // Auto-add article to newly created collection
                    Task {
                        _ = try? await appState.supabase.addArticleToCollection(
                            collectionId: newCollection.id,
                            articleId: articleId
                        )
                        memberOf.insert(newCollection.id)
                    }
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let allCollections = appState.supabase.fetchCollections()
            async let articleCollections = appState.supabase.fetchArticleCollections(articleId: articleId)

            collections = try await allCollections
            let current = try await articleCollections
            memberOf = Set(current.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleMembership(_ collection: CompanionCollection) async {
        do {
            if memberOf.contains(collection.id) {
                try await appState.supabase.removeArticleFromCollection(
                    collectionId: collection.id,
                    articleId: articleId
                )
                memberOf.remove(collection.id)
            } else {
                _ = try await appState.supabase.addArticleToCollection(
                    collectionId: collection.id,
                    articleId: articleId
                )
                memberOf.insert(collection.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
