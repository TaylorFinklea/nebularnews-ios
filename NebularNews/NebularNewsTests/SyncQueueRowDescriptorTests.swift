import Foundation
import Testing
@testable import NebularNews

// MARK: - SyncQueueRowDescriptor unit tests

struct SyncQueueRowDescriptorTests {

    // MARK: - Action type label / icon mapping

    @Test func readActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("read")
        #expect(info.label == "Mark read")
        #expect(info.icon == "checkmark.circle")
    }

    @Test func saveActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("save")
        #expect(info.label == "Save article")
        #expect(info.icon == "bookmark")
    }

    @Test func saveActionWithSavedFalseProducesUnsaveLabel() {
        let payload = #"{"saved":false}"#
        let info = ActionTypeInfo.for_("save", payload: payload)
        #expect(info.label == "Unsave article")
        #expect(info.icon == "bookmark")
    }

    @Test func saveActionWithSavedTrueProducesSaveLabel() {
        let payload = #"{"saved":true}"#
        let info = ActionTypeInfo.for_("save", payload: payload)
        #expect(info.label == "Save article")
    }

    @Test func reactionActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("reaction")
        #expect(info.label == "Set reaction")
        #expect(info.icon == "hand.thumbsup")
    }

    @Test func tagAddActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("tag_add")
        #expect(info.label == "Add tag")
        #expect(info.icon == "tag")
    }

    @Test func tagRemoveActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("tag_remove")
        #expect(info.label == "Remove tag")
        #expect(info.icon == "tag.slash")
    }

    @Test func feedSettingsActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("feed_settings")
        #expect(info.label == "Update feed settings")
        #expect(info.icon == "slider.horizontal.3")
    }

    @Test func subscribeFeedActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("subscribe_feed")
        #expect(info.label == "Add feed")
        #expect(info.icon == "plus.rectangle.on.rectangle")
    }

    @Test func unsubscribeFeedActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("unsubscribe_feed")
        #expect(info.label == "Remove feed")
        #expect(info.icon == "minus.rectangle")
    }

    @Test func readingPositionActionHasCorrectLabelAndIcon() {
        let info = ActionTypeInfo.for_("reading_position")
        #expect(info.label == "Save reading position")
        #expect(info.icon == "book")
    }

    @Test func unknownActionTypeFallsBackToRawStringAndQuestionIcon() {
        let info = ActionTypeInfo.for_("future_unknown_action")
        #expect(info.label == "future_unknown_action")
        #expect(info.icon == "questionmark.circle")
    }

    // MARK: - Resource title resolution fallback

    @Test func articleTitleFallsBackToArticlePrefix() {
        let action = makePendingAction(type: "read", articleId: "abc123xyz789")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        #expect(descriptor.targetTitle == "Article abc123xy")
    }

    @Test func articleTitleUsesResolvedTitleWhenAvailable() {
        let action = makePendingAction(type: "read", articleId: "abc123")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "The Verge Headline" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        #expect(descriptor.targetTitle == "The Verge Headline")
    }

    @Test func feedTitleFallsBackToFeedPrefix() {
        let action = makePendingAction(type: "feed_settings", articleId: "feed-id-12345678")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        // articleId "feed-id-12345678".prefix(8) == "feed-id-"
        #expect(descriptor.targetTitle == "Feed feed-id-")
    }

    @Test func subscribeFeedUsesURLDirectly() {
        let url = "https://example.com/rss"
        let action = makePendingAction(type: "subscribe_feed", articleId: url)
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        #expect(descriptor.targetTitle == url)
    }

    // MARK: - Discard confirmation body

    @Test func discardBodyForReadAction() {
        let action = makePendingAction(type: "read", articleId: "a1")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "The unread/read change for Test Article will be lost.")
    }

    @Test func discardBodyForSaveAction() {
        let action = makePendingAction(type: "save", articleId: "a1", payload: #"{"saved":true}"#)
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "The save/unsave change for Test Article will be lost.")
    }

    @Test func discardBodyForReactionAction() {
        let action = makePendingAction(type: "reaction", articleId: "a1")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "Your reaction on Test Article will be lost.")
    }

    @Test func discardBodyForTagAddWithName() {
        let payload = #"{"tagName":"evergreen","tagId":null}"#
        let action = makePendingAction(type: "tag_add", articleId: "a1", payload: payload)
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "The tag evergreen will not be added to Test Article.")
    }

    @Test func discardBodyForTagRemove() {
        let action = makePendingAction(type: "tag_remove", articleId: "a1")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "The tag will not be removed from Test Article.")
    }

    @Test func discardBodyForFeedSettings() {
        let payload = #"{"paused":true,"maxArticlesPerDay":50,"minScore":3}"#
        let action = makePendingAction(type: "feed_settings", articleId: "f1", payload: payload)
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in "The Verge" },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body.hasPrefix("Your settings change for The Verge will be lost"))
    }

    @Test func discardBodyForSubscribeFeed() {
        let url = "https://example.com/rss"
        let action = makePendingAction(type: "subscribe_feed", articleId: url)
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "\(url) will not be added to your feeds.")
    }

    @Test func discardBodyForUnsubscribeFeed() {
        let action = makePendingAction(type: "unsubscribe_feed", articleId: "f1")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in nil },
            cachedFeedTitle: { _ in "The Verge" },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "The Verge will not be removed.")
    }

    @Test func discardBodyForReadingPosition() {
        let action = makePendingAction(type: "reading_position", articleId: "a1")
        let descriptor = SyncQueueRowDescriptor.from(
            action,
            cachedArticleTitle: { _ in "Test Article" },
            cachedFeedTitle: { _ in nil },
            isOffline: false
        )
        let body = descriptor.discardConfirmationBody()
        #expect(body == "Your reading position for Test Article will be lost.")
    }

    // MARK: - Report redaction

    @Test func redactionReplacesStringsOver256Chars() {
        let longString = String(repeating: "x", count: 1000)
        let payload = "{\"content\":\"\(longString)\"}"
        let redacted = applyRedaction(payload: payload, actionType: "save")
        guard let dict = redacted as? [String: Any],
              let val = dict["content"] as? String else {
            Issue.record("Expected dict with content key")
            return
        }
        #expect(val == "<redacted: length=1000>")
    }

    @Test func redactionStripsFeedURLQueryString() {
        let payload = #"{"url":"https://example.com/path?token=abc","scrapeMode":null}"#
        let redacted = applyRedaction(payload: payload, actionType: "subscribe_feed")
        guard let dict = redacted as? [String: Any],
              let url = dict["url"] as? String else {
            Issue.record("Expected dict with url key")
            return
        }
        #expect(url == "https://example.com/path")
    }

    @Test func redactionPreservesShortStrings() {
        let payload = #"{"saved":true}"#
        let redacted = applyRedaction(payload: payload, actionType: "save")
        // Should remain as-is for the saved bool (not a string field)
        // The result should be parseable and not contain redacted markers
        if let dict = redacted as? [String: Any] {
            #expect(dict["saved"] as? Bool == true)
        }
    }

    // MARK: - Helpers

    private func makePendingAction(
        type: String,
        articleId: String,
        payload: String = "{}",
        retryCount: Int = 0,
        lastError: String? = nil
    ) -> PendingAction {
        let action = PendingAction(actionType: type, articleId: articleId, payload: payload)
        action.retryCount = retryCount
        action.lastError = lastError
        return action
    }

    /// Replicate the redaction logic from SyncQueueDeadLetterDetailSheet for testing.
    private func applyRedaction(payload: String, actionType: String) -> Any {
        guard let data = payload.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return payload
        }

        for key in obj.keys {
            if let str = obj[key] as? String, str.count >= 256 {
                obj[key] = "<redacted: length=\(str.count)>"
            }
        }

        if actionType == "subscribe_feed", let urlStr = obj["url"] as? String,
           var components = URLComponents(string: urlStr) {
            components.query = nil
            obj["url"] = components.string ?? urlStr
        }

        return obj
    }
}
