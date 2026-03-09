import SwiftUI

struct FeedSwipeActionDescriptor {
    let title: String
    let systemImage: String
    let tint: Color
    let handler: () -> Void
}

struct FeedSwipeContainer<Content: View>: View {
    private let cornerRadius: CGFloat
    private let leadingAction: FeedSwipeActionDescriptor
    private let trailingAction: FeedSwipeActionDescriptor
    private let onTap: (() -> Void)?
    private let content: Content

    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalSwipe = false
    @State private var suppressTap = false

    private let maxReveal: CGFloat = 108
    private let triggerThreshold: CGFloat = 72
    private let tapSuppressionThreshold: CGFloat = 6

    init(
        cornerRadius: CGFloat,
        leadingAction: FeedSwipeActionDescriptor,
        trailingAction: FeedSwipeActionDescriptor,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        ZStack {
            if dragOffset > 0 {
                actionBackground(for: leadingAction, alignment: .leading)
            } else if dragOffset < 0 {
                actionBackground(for: trailingAction, alignment: .trailing)
            }

            tappableContent
                .offset(x: dragOffset)
                .allowsHitTesting(!isHorizontalSwipe)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction(named: Text("Open Article")) {
            guard onTap != nil, !suppressTap, dragOffset == 0 else { return }
            onTap?()
        }
        .accessibilityAction(named: Text(leadingAction.title)) {
            leadingAction.handler()
        }
        .accessibilityAction(named: Text(trailingAction.title)) {
            trailingAction.handler()
        }
        .animation(.snappy(duration: 0.18), value: dragOffset)
    }

    @ViewBuilder
    private var tappableContent: some View {
        content
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                guard onTap != nil, !suppressTap, dragOffset == 0 else { return }
                onTap?()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: tapSuppressionThreshold, coordinateSpace: .local)
            .onChanged { value in
                if shouldSuppressTap(for: value.translation) {
                    suppressTap = true
                }

                guard shouldTrackSwipe(for: value.translation) else { return }

                isHorizontalSwipe = true
                dragOffset = min(max(value.translation.width, -maxReveal), maxReveal)
            }
            .onEnded { value in
                let endedHorizontalSwipe = isHorizontalSwipe
                defer { isHorizontalSwipe = false }

                guard endedHorizontalSwipe else {
                    resetDrag()
                    if suppressTap {
                        releaseTapSuppression()
                    }
                    return
                }

                let predictedOffset = min(max(value.predictedEndTranslation.width, -maxReveal), maxReveal)

                if predictedOffset >= triggerThreshold {
                    perform(leadingAction)
                } else if predictedOffset <= -triggerThreshold {
                    perform(trailingAction)
                } else {
                    resetDrag()
                }

                releaseTapSuppression()
            }
    }

    private func shouldTrackSwipe(for translation: CGSize) -> Bool {
        if isHorizontalSwipe {
            return true
        }

        guard abs(translation.width) > 10 else {
            return false
        }

        return abs(translation.width) > abs(translation.height)
    }

    private func shouldSuppressTap(for translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) >= tapSuppressionThreshold
    }

    private func actionBackground(
        for action: FeedSwipeActionDescriptor,
        alignment: Alignment
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(action.tint.gradient)
            .overlay(alignment: alignment) {
                HStack(spacing: 8) {
                    if alignment == .trailing {
                        Spacer(minLength: 0)
                    }

                    Label(action.title, systemImage: action.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .opacity(labelOpacity)
                        .scaleEffect(labelScale)

                    if alignment == .leading {
                        Spacer(minLength: 0)
                    }
                }
            }
    }

    private var labelOpacity: Double {
        min(max(Double(abs(dragOffset) / 36), 0.22), 1)
    }

    private var labelScale: CGFloat {
        min(max(abs(dragOffset) / maxReveal, 0.85), 1)
    }

    private func perform(_ action: FeedSwipeActionDescriptor) {
        action.handler()
        resetDrag()
    }

    private func resetDrag() {
        dragOffset = 0
    }

    private func releaseTapSuppression() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            suppressTap = false
        }
    }
}
