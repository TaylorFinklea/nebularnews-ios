#if os(iOS)
import ActivityKit
import Foundation
import os

@MainActor
enum BriefLiveActivityController {
    private static let logger = Logger(subsystem: "com.nebularnews", category: "BriefLiveActivity")

    static func start(editionLabel: String) -> Activity<BriefActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities not enabled — skipping start")
            return nil
        }

        let attributes = BriefActivityAttributes(editionLabel: editionLabel)
        let initial = BriefActivityAttributes.ContentState(
            stage: .generating,
            firstBullet: nil,
            bulletCount: 0
        )

        do {
            return try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initial, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            logger.error("Failed to start brief Live Activity: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func finish(
        activity: Activity<BriefActivityAttributes>?,
        firstBullet: String?,
        bulletCount: Int
    ) async {
        guard let activity else { return }
        let state = BriefActivityAttributes.ContentState(
            stage: .done,
            firstBullet: firstBullet,
            bulletCount: bulletCount
        )
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(30))
        )
    }

    static func fail(activity: Activity<BriefActivityAttributes>?) async {
        guard let activity else { return }
        let state = BriefActivityAttributes.ContentState(
            stage: .failed,
            firstBullet: nil,
            bulletCount: 0
        )
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(8))
        )
    }
}
#endif
