import SwiftUI

struct EditCollectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let collection: CompanionCollection
    var onUpdate: (CompanionCollection) -> Void

    @State private var name: String
    @State private var description: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var isSaving = false
    @State private var errorMessage = ""

    private let colorOptions = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5856D6", "#AF52DE", "#FF2D55",
    ]

    private let iconOptions = [
        "folder", "star", "heart", "bookmark",
        "tag", "flag", "bolt", "lightbulb",
        "newspaper", "book", "graduationcap", "briefcase",
    ]

    init(collection: CompanionCollection, onUpdate: @escaping (CompanionCollection) -> Void) {
        self.collection = collection
        self.onUpdate = onUpdate
        _name = State(initialValue: collection.name)
        _description = State(initialValue: collection.description ?? "")
        _selectedColor = State(initialValue: collection.color ?? "#007AFF")
        _selectedIcon = State(initialValue: collection.icon ?? "folder")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $name)
                }

                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if hex == selectedColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(icon == selectedIcon ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .onTapGesture { selectedIcon = icon }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await appState.supabase.updateCollection(
                id: collection.id,
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                color: selectedColor,
                icon: selectedIcon
            )
            onUpdate(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
