import SwiftUI

/// Read-only chat surface for one historical day. Renders the same
/// brief seed cards + chat bubbles as the live Today tab, minus the
/// affordances that wouldn't make sense on a closed day:
/// no input bar, no Save / Tell-me-more on bullets, no swipe actions,
/// no streaming bubble. Article taps still push the article detail —
/// review of past conversations should naturally support clicking
/// through to anything the assistant referenced.
struct DayConversationView: View {
    @Environment(AppState.self) private var appState

    let day: CompanionConversationDay

    @State private var detail: CompanionConversationDayDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var openArticleId: String?

    private var messages: [CompanionChatMessage] {
        (detail?.messages ?? []).filter { $0.role != "system" }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            ForEach(messages) { msg in
                messageRow(for: msg)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(titleString)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .overlay {
            if isLoading && messages.isEmpty {
                ProgressView()
            }
        }
        .navigationDestination(item: $openArticleId) { articleId in
            CompanionArticleDetailView(articleId: articleId)
        }
    }

    @ViewBuilder
    private func messageRow(for msg: CompanionChatMessage) -> some View {
        if msg.kind == "brief_seed", let brief = SeededBrief.parse(content: msg.content) {
            briefSection(brief: brief, anchorId: msg.id)
        } else {
            AssistantChatBubble(message: msg) { articleId in
                openArticleId = articleId
            }
            .id(msg.id)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
    }

    @ViewBuilder
    private func briefSection(brief: SeededBrief, anchorId: String) -> some View {
        Section {
            ForEach(brief.bullets) { bullet in
                // Read-only mode hides Save / Tell me more chips, and we
                // skip the Today-only swipe actions entirely so a past
                // brief can't get retroactively reacted to.
                BriefBulletCard(
                    bullet: bullet,
                    onAction: { action in
                        if case .openArticle(let id) = action { openArticleId = id }
                    },
                    interactive: false
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        } header: {
            BriefSectionHeader(brief: brief)
                .id(anchorId)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - Title

    private var titleString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day.day) else { return day.day }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let cmp = calendar.startOfDay(for: date)
        if cmp == today { return "Today" }
        if cmp == yesterday { return "Yesterday" }
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Data

    private func load() async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await appState.supabase.fetchConversationDay(date: day.day)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
