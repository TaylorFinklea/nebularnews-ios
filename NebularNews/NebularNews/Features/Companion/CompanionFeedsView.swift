import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NebularNewsKit

// MARK: - Feeds

struct CompanionFeedsView: View {
    @Environment(AppState.self) private var appState

    @State private var feeds: [CompanionFeed] = []
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingAddFeed = false
    @State private var showingImport = false
    @State private var deletingFeed: CompanionFeed?

    var body: some View {
        List {
            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage) {
                    Task { await loadFeeds() }
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            ForEach(feeds) { feed in
                HStack(spacing: 12) {
                    Circle()
                        .fill(feedStatusColor(feed))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title?.isEmpty == false ? feed.title! : feed.url)
                            .font(.headline)

                        HStack(spacing: 8) {
                            if let articleCount = feed.articleCount {
                                Text("\(articleCount) articles")
                            }
                            if let lastPolled = feed.lastPolledAt {
                                Text("Updated \(relativeTime(lastPolled))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if feed.disabled == 1 {
                            Label("Disabled", systemImage: "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let errorCount = feed.errorCount, errorCount > 0 {
                            Label("\(errorCount) consecutive error\(errorCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deletingFeed = feed
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await exportOPML() }
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if isLoading && feeds.isEmpty {
                ProgressView("Loading feeds…")
            }
        }
        .task {
            if feeds.isEmpty {
                await loadFeeds()
            }
        }
        .refreshable { await loadFeeds() }
        .sheet(isPresented: $showingAddFeed) {
            CompanionAddFeedSheet { url in
                Task {
                    do {
                        _ = try await appState.mobileAPI.addFeed(url: url)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            CompanionOPMLImportSheet { xml in
                Task {
                    do {
                        _ = try await appState.mobileAPI.importOPML(xml: xml)
                        await loadFeeds()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert(
            "Delete Feed",
            isPresented: Binding(
                get: { deletingFeed != nil },
                set: { if !$0 { deletingFeed = nil } }
            ),
            presenting: deletingFeed
        ) { feed in
            Button("Delete", role: .destructive) {
                Task { await deleteFeed(feed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { feed in
            Text("Delete \"\(feed.title ?? feed.url)\" and all its exclusive articles?")
        }
    }

    private func feedStatusColor(_ feed: CompanionFeed) -> Color {
        if feed.disabled == 1 { return .gray }
        if let errorCount = feed.errorCount, errorCount >= 3 { return .red }
        if let errorCount = feed.errorCount, errorCount > 0 { return .yellow }
        return .green
    }

    private func relativeTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func loadFeeds() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feeds = try await appState.mobileAPI.fetchFeeds()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFeed(_ feed: CompanionFeed) async {
        do {
            _ = try await appState.mobileAPI.deleteFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportOPML() async {
        do {
            let xml = try await appState.mobileAPI.exportOPML()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("nebular-news.opml")
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else { return }
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Feed Sheet

private struct CompanionAddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String) -> Void
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - OPML Import Sheet

private struct CompanionOPMLImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (String) -> Void
    @State private var showingFilePicker = false
    @State private var importedXML: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Select an OPML file to import feeds.")
                    .foregroundStyle(.secondary)
                Button("Choose File") {
                    showingFilePicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Import OPML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.xml, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard let url = try? result.get().first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let xml = try? String(contentsOf: url, encoding: .utf8) {
                    onImport(xml)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
