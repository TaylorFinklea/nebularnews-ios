import SwiftUI
import NebularNewsKit

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String, String) async -> Void

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed.xml", text: $urlText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Feed URL")
                } footer: {
                    Text("Enter the URL of an RSS, Atom, or JSON Feed.")
                }

                Section {
                    TextField("My Feed", text: $titleText)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("Optional. If left blank, the feed's title will be used once polled.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addFeed() }
                    }
                    .disabled(normalizedUrl == nil || isAdding)
                }
            }
            .disabled(isAdding)
            .overlay {
                if isAdding {
                    ProgressView()
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Validation

    private var normalizedUrl: String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Auto-add https:// if no scheme present
        if !trimmed.contains("://") {
            let withScheme = "https://\(trimmed)"
            return URL(string: withScheme) != nil ? withScheme : nil
        }
        return URL(string: trimmed) != nil ? trimmed : nil
    }

    // MARK: - Actions

    private func addFeed() async {
        guard let url = normalizedUrl else {
            errorMessage = "Please enter a valid URL."
            return
        }

        isAdding = true
        errorMessage = nil

        await onAdd(url, titleText.trimmingCharacters(in: .whitespacesAndNewlines))

        isAdding = false
        dismiss()
    }
}
