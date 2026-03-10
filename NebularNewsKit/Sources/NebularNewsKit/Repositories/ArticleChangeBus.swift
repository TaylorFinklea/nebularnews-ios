import Foundation

public enum ArticleChangeBus {
    public static let todaySnapshotChanged = Notification.Name("NebularNews.todaySnapshotChanged")
    public static let feedPageMightChange = Notification.Name("NebularNews.feedPageMightChange")
    public static let readingListChanged = Notification.Name("NebularNews.readingListChanged")
    public static let articleChanged = Notification.Name("NebularNews.articleChanged")
    public static let processingQueueChanged = Notification.Name("NebularNews.processingQueueChanged")

    public static func postTodaySnapshotChanged() {
        NotificationCenter.default.post(name: todaySnapshotChanged, object: nil)
    }

    public static func postFeedPageMightChange() {
        NotificationCenter.default.post(name: feedPageMightChange, object: nil)
    }

    public static func postReadingListChanged() {
        NotificationCenter.default.post(name: readingListChanged, object: nil)
    }

    public static func postArticleChanged(id: String) {
        NotificationCenter.default.post(
            name: articleChanged,
            object: nil,
            userInfo: ["articleID": id]
        )
    }

    public static func postProcessingQueueChanged() {
        NotificationCenter.default.post(name: processingQueueChanged, object: nil)
    }
}
