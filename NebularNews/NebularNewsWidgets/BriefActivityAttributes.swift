import ActivityKit
import Foundation

struct BriefActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: Stage
        var firstBullet: String?
        var bulletCount: Int

        enum Stage: String, Codable, Hashable {
            case generating
            case done
            case failed
        }
    }

    let editionLabel: String
}
