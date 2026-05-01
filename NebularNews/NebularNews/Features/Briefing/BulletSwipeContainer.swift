import SwiftUI

/// A horizontal swipe-reveal container for the brief bullet card.
///
/// SwiftUI's `.swipeActions` modifier only works inside `List`, but the
/// Today thread renders bullets inside a chat-style `LazyVStack` so a
/// list refactor would ripple through the whole view. This wraps any
/// content view, lets the user drag horizontally to expose a row of
/// action buttons on either edge, and snaps closed after the user taps
/// one or releases past the threshold.
struct BulletSwipeContainer<Content: View>: View {
    struct Action: Identifiable {
        let id = UUID()
        let label: String
        let systemImage: String
        let tint: Color
        let perform: () -> Void
    }

    let leading: [Action]
    let trailing: [Action]
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private var actionWidth: CGFloat { 72 }
    private var leadingFullWidth: CGFloat { CGFloat(leading.count) * actionWidth }
    private var trailingFullWidth: CGFloat { CGFloat(trailing.count) * actionWidth }

    private var liveOffset: CGFloat { offset + dragOffset }

    var body: some View {
        ZStack {
            actionStrip(.trailing)
            actionStrip(.leading)

            content()
                .offset(x: liveOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragOffset) { value, state, _ in
                            // Constrain to the available action width so the card
                            // never drifts past the buttons on either side.
                            let raw = value.translation.width
                            let proposed = offset + raw
                            let clamped = min(max(proposed, -trailingFullWidth), leadingFullWidth)
                            state = clamped - offset
                        }
                        .onEnded { value in
                            let final = offset + value.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                if final > leadingFullWidth / 2 && !leading.isEmpty {
                                    offset = leadingFullWidth
                                } else if final < -trailingFullWidth / 2 && !trailing.isEmpty {
                                    offset = -trailingFullWidth
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    @ViewBuilder
    private func actionStrip(_ edge: HorizontalEdge) -> some View {
        let actions = edge == .leading ? leading : trailing
        let revealed = edge == .leading ? max(liveOffset, 0) : max(-liveOffset, 0)
        if !actions.isEmpty {
            HStack(spacing: 0) {
                if edge == .trailing { Spacer() }
                ForEach(actions) { action in
                    Button {
                        action.perform()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            offset = 0
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: action.systemImage)
                                .font(.body)
                            Text(action.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: actionWidth)
                        .frame(maxHeight: .infinity)
                        .background(action.tint)
                    }
                    .buttonStyle(.plain)
                }
                if edge == .leading { Spacer() }
            }
            .opacity(revealed > 1 ? 1 : 0)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private enum HorizontalEdge { case leading, trailing }
