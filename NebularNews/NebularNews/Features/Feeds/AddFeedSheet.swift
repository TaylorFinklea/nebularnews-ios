import SwiftUI
import UniformTypeIdentifiers
import NebularNewsKit

enum AddFeedRequest {
    case single(url: String, title: String)
    case opml(entries: [OPMLFeedEntry])
}

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSubmit: (AddFeedRequest) async -> String?

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var opmlText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

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
                    Text("Add a single RSS, Atom, or JSON Feed.")
                }

                Section {
                    TextField("My Feed", text: $titleText)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("Optional. If left blank, the feed's title will be used once polled.")
                }

                Section {
                    TextEditor(text: $opmlText)
                        .frame(minHeight: 160)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Import Pasted OPML") {
                        Task { await importPastedOPML() }
                    }
                    .disabled(opmlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)

                    Button("Import OPML File") {
                        showFileImporter = true
                    }
                    .disabled(isAdding)
                } header: {
                    Text("OPML Import")
                } footer: {
                    Text("Paste OPML text or pick a `.opml`, `.xml`, or text file exported from another reader.")
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
                        Task { await addSingleFeed() }
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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.xml, .plainText, opmlContentType],
            allowsMultipleSelection: false
        ) { result in
            Task { await importSelectedFile(result) }
        }
        .presentationDetents([.large])
    }

    private var opmlContentType: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }

    // MARK: - Validation

    private var normalizedUrl: String? {
        normalizeURL(urlText)
    }

    private func normalizeURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("://") {
            let withScheme = "https://\(trimmed)"
            return URL(string: withScheme) != nil ? withScheme : nil
        }

        return URL(string: trimmed) != nil ? trimmed : nil
    }

    private func normalizedOPMLEntries(_ entries: [OPMLFeedEntry]) -> [OPMLFeedEntry] {
        var seenURLs = Set<String>()

        return entries.compactMap { entry in
            guard let normalizedURL = normalizeURL(entry.feedURL),
                  seenURLs.insert(normalizedURL).inserted
            else {
                return nil
            }

            return OPMLFeedEntry(
                feedURL: normalizedURL,
                title: entry.title.trimmingCharacters(in: .whitespacesAndNewlines),
                siteURL: entry.siteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: - Actions

    private func addSingleFeed() async {
        guard let url = normalizedUrl else {
            errorMessage = "Please enter a valid URL."
            return
        }

        await submit(.single(
            url: url,
            title: titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }

    private func importPastedOPML() async {
        let trimmed = opmlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Paste an OPML document first."
            return
        }

        do {
            let entries = normalizedOPMLEntries(try OPMLParser.parse(string: trimmed))
            guard !entries.isEmpty else {
                errorMessage = "No feed URLs were found in the pasted OPML."
                return
            }

            await submit(.opml(entries: entries))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importSelectedFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let entries = normalizedOPMLEntries(try OPMLParser.parse(data: data))
            guard !entries.isEmpty else {
                errorMessage = "No feed URLs were found in that OPML file."
                return
            }

            await submit(.opml(entries: entries))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit(_ request: AddFeedRequest) async {
        isAdding = true
        errorMessage = nil

        let returnedError = await onSubmit(request)

        isAdding = false

        if let returnedError, !returnedError.isEmpty {
            errorMessage = returnedError
            return
        }

        dismiss()
    }
}
