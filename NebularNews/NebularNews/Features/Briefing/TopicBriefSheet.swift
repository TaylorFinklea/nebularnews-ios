import SwiftUI

/// Tag-picker sheet that generates a brief filtered to one tag and
/// hands the resulting brief id back to the parent so it can navigate
/// to BriefDetailView. The endpoint already exists at /api/brief/generate;
/// this view is purely the iOS UI surface.
struct TopicBriefSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// Called with the brief id once the topic brief has been generated.
    /// Parent uses this to push BriefDetailView onto its NavigationStack.
    let onGenerated: (String) -> Void

    @State private var allTags: [CompanionTagWithCount] = []
    @State private var settings: CompanionSettingsPayload?
    @State private var query: String = ""
    @State private var isLoadingTags = false
    @State private var generatingTagId: String?
    @State private var errorMessage: String?

    private var filteredTags: [CompanionTagWithCount] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                if isLoadingTags && allTags.isEmpty {
                    Section { ProgressView() }
                } else if allTags.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No tags yet",
                            systemImage: "tag",
                            description: Text("Tag some articles first — topic briefs filter your news to one tag at a time.")
                        )
                    }
                } else {
                    Section {
                        ForEach(filteredTags) { tag in
                            Button { Task { await generate(for: tag) } } label: {
                                row(for: tag)
                            }
                            .disabled(generatingTagId != nil)
                        }
                    } footer: {
                        Text("Pick a tag and we'll generate a brief filtered to articles with that tag.")
                    }
                }
            }
            .searchable(text: $query, prompt: "Filter tags")
            .navigationTitle("Topic brief")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(generatingTagId != nil)
                }
            }
            .task { await loadTags() }
        }
    }

    @ViewBuilder
    private func row(for tag: CompanionTagWithCount) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tagColor(for: tag))
                .frame(width: 10, height: 10)
            Text("#\(tag.name)")
                .foregroundStyle(.primary)
            Spacer()
            if generatingTagId == tag.id {
                ProgressView()
            } else {
                Text("\(tag.articleCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func tagColor(for tag: CompanionTagWithCount) -> Color {
        guard let hex = tag.color else { return .accentColor }
        return Color(hex: hex)
    }

    private func loadTags() async {
        guard allTags.isEmpty else { return }
        isLoadingTags = true
        defer { isLoadingTags = false }
        async let tagsTask: [CompanionTagWithCount] = appState.supabase.fetchTags()
        async let settingsTask: CompanionSettingsPayload = appState.supabase.fetchSettings()
        do {
            allTags = try await tagsTask
        } catch {
            errorMessage = "Couldn't load tags: \(error.localizedDescription)"
        }
        // Settings is non-critical for the picker UI — we only need it to
        // reuse the user's preferred depth when generating. If it fails,
        // fall through with depth=nil so the server uses its default.
        settings = try? await settingsTask
    }

    private func generate(for tag: CompanionTagWithCount) async {
        guard generatingTagId == nil else { return }
        generatingTagId = tag.id
        errorMessage = nil
        defer { generatingTagId = nil }

        struct GenBody: Encodable {
            let topic_tag_id: String
            let depth: String?
            let lookback_hours: Int
        }
        struct GenResponse: Decodable {
            let id: String?
        }

        let depth = settings?.newsBriefConfig.depth
        let lookbackHours = settings?.newsBriefConfig.lookbackHours ?? 12

        do {
            let response: GenResponse = try await APIClient.shared.request(
                method: "POST",
                path: "api/brief/generate",
                body: GenBody(topic_tag_id: tag.id, depth: depth, lookback_hours: lookbackHours)
            )
            guard let id = response.id else {
                errorMessage = "No brief generated — try a tag with more recent articles."
                return
            }
            onGenerated(id)
            dismiss()
        } catch {
            errorMessage = "Couldn't generate brief: \(error.localizedDescription)"
        }
    }
}
