import SwiftUI
import WidgetKit

@main
struct NebularNewsWidgets: WidgetBundle {
    var body: some Widget {
        StatsWidget()
        TopArticleWidget()
        ReadingQueueWidget()
        BriefLiveActivity()
    }
}
