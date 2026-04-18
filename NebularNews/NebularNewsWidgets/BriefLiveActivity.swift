#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct BriefLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BriefActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            lockScreenView(context: context)
                .activityBackgroundTint(Color.accentColor.opacity(0.15))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.editionLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<BriefActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(.tint)
                Text(context.attributes.editionLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                stageBadge(context.state.stage)
            }
            switch context.state.stage {
            case .generating:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Summarizing today's stories…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .done:
                if let bullet = context.state.firstBullet {
                    Text(bullet)
                        .font(.callout)
                        .lineLimit(3)
                }
                if context.state.bulletCount > 1 {
                    Text("+ \(context.state.bulletCount - 1) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed:
                Text("Couldn't generate brief")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<BriefActivityAttributes>) -> some View {
        switch context.state.stage {
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Summarizing today's stories…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .done:
            VStack(alignment: .leading, spacing: 4) {
                if let bullet = context.state.firstBullet {
                    Text(bullet)
                        .font(.callout)
                        .lineLimit(3)
                }
                if context.state.bulletCount > 1 {
                    Text("+ \(context.state.bulletCount - 1) more bullets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed:
            Text("Couldn't generate brief")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func compactTrailingView(context: ActivityViewContext<BriefActivityAttributes>) -> some View {
        switch context.state.stage {
        case .generating:
            ProgressView()
                .scaleEffect(0.7)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func stageBadge(_ stage: BriefActivityAttributes.ContentState.Stage) -> some View {
        switch stage {
        case .generating:
            Text("Generating")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        case .done:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        }
    }
}
#endif
