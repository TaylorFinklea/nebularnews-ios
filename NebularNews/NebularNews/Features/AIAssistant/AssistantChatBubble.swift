import SwiftUI

/// Renders an assistant message with parsed article card references.
struct AssistantChatBubble: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator
    let message: CompanionChatMessage
    var onArticleTap: ((String) -> Void)?

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        // System messages (context markers) render as segment dividers.
        if message.role == "system" {
            let label = message.content
                .replacingOccurrences(of: "[Context: ", with: "")
                .replacingOccurrences(of: "]", with: "")
            AssistantSegmentDivider(label: label)
        } else {
            HStack(alignment: .top, spacing: 8) {
                if isUser { Spacer(minLength: 40) }

                if !isUser {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .frame(width: 24, height: 24)
                        .background(Color.purple.opacity(0.1), in: Circle())
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    if isUser {
                        Text(message.content)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        // Parse and render segments with article cards.
                        let segments = AssistantMessageParser.parse(message.content)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                segmentView(segment)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.platformSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if let model = message.model, !isUser {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }

                if !isUser { Spacer(minLength: 40) }
            }
        }
    }

    @ViewBuilder
    fileprivate func segmentView(_ segment: AssistantContentSegment) -> some View {
        AssistantSegmentView(segment: segment, onArticleTap: onArticleTap)
    }
}

/// Renders one parsed assistant segment (text / article card / tool
/// chip). Extracted from AssistantChatBubble so the live-streaming
/// bubble in TodayBriefingView can reuse the exact same visuals —
/// during streaming, parsing `coordinator.streamingContent` and
/// running each segment through this view replaces raw marker text
/// like `[[tool:get_trending_topics:Fetched...]]` with the polished
/// chip the user sees on committed messages.
struct AssistantSegmentView: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator

    let segment: AssistantContentSegment
    var onArticleTap: ((String) -> Void)?

    var body: some View {
        switch segment {
        case .text(let text):
            Text(LocalizedStringKey(text))
                .font(.system(.body, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
        case .articleCard(let id, let title):
            Button {
                onArticleTap?(id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        case .toolResult(_, let summary, let succeeded, let undo):
            HStack(spacing: 6) {
                Image(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(succeeded ? .green : .orange)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let undo, succeeded {
                    Button {
                        Task { await coordinator.undoTool(tool: undo.tool, argsB64: undo.argsB64) }
                    } label: {
                        Text("Undo")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((succeeded ? Color.green : Color.orange).opacity(0.1))
            .clipShape(Capsule())
        }
    }
}
