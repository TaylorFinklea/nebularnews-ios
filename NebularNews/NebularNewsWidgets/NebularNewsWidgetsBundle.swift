import WidgetKit
import SwiftUI

@main
struct NebularNewsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StatsWidget()
        TopArticleWidget()
        ReadingQueueWidget()
        NewsBriefWidget()
        #if os(iOS)
        BriefLiveActivity()
        #endif
    }
}
