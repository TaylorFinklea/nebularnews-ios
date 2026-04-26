import UserNotifications
import UniformTypeIdentifiers

/// Notification Service Extension for NebularNews push notifications.
///
/// When a brief push arrives with `mutable-content: 1` set by the server
/// (see `apns.ts`), iOS hands the payload to this extension before showing
/// the notification. We do two things:
///
/// 1. **Body enrichment** — replace the single-bullet body the server sets
///    with the first 2 bullets joined by a newline, drawn from the
///    `bullets` array in the payload's `userInfo`.
///
/// 2. **Image attachment** — download the URL in `userInfo.image_url` to a
///    temp file and attach it as a `UNNotificationAttachment` so it
///    appears inline in the lock-screen / notification banner.
///
/// Both are best-effort. We have a hard 30-second wall-time budget; if
/// either step fails or the image takes too long, we fall through to the
/// original payload contents. `serviceExtensionTimeWillExpire()` is the
/// safety net for cases where the system kills the extension early.
class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    private static let imageDownloadTimeout: TimeInterval = 8

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttempt = (request.content.mutableCopy() as? UNMutableNotificationContent)
        guard let mutable = bestAttempt else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo

        // 1. Body enrichment from `bullets` array.
        if let bullets = userInfo["bullets"] as? [String], !bullets.isEmpty {
            mutable.body = bullets.prefix(2).joined(separator: "\n")
        }

        // 2. Image attachment, gated on a parseable URL.
        guard
            let imageString = userInfo["image_url"] as? String,
            let imageURL = URL(string: imageString)
        else {
            contentHandler(mutable)
            return
        }

        downloadAttachment(from: imageURL) { attachment in
            if let attachment {
                mutable.attachments = [attachment]
            }
            contentHandler(mutable)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // System is about to kill us. Cancel the download and ship whatever
        // content we've got — better a body-only notification than nothing.
        downloadTask?.cancel()
        if let handler = contentHandler, let mutable = bestAttempt {
            handler(mutable)
        }
    }

    // MARK: - Private

    /// Downloads `url` to a temp file and constructs a `UNNotificationAttachment`.
    /// Calls `completion(nil)` on any failure so the caller can fall through.
    private func downloadAttachment(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.imageDownloadTimeout
        config.timeoutIntervalForResource = Self.imageDownloadTimeout
        let session = URLSession(configuration: config)

        let task = session.downloadTask(with: url) { tempURL, response, error in
            // URLSession returns the file at a temp location it owns; we
            // need to move it somewhere the notification framework can read
            // (and won't delete out from under us before iOS shows the
            // notification).
            guard error == nil, let tempURL else {
                completion(nil); return
            }

            let typeHint = inferUTType(from: response, fallbackURL: url)
            let suggestedExt = typeHint.preferredFilenameExtension ?? "jpg"
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(suggestedExt)

            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
            } catch {
                completion(nil); return
            }

            do {
                let attachment = try UNNotificationAttachment(
                    identifier: "preview",
                    url: dest,
                    options: [
                        UNNotificationAttachmentOptionsTypeHintKey: typeHint.identifier,
                    ]
                )
                completion(attachment)
            } catch {
                try? FileManager.default.removeItem(at: dest)
                completion(nil)
            }
        }
        downloadTask = task
        task.resume()
    }
}

/// Best-effort UTType inference. Prefers the response's MIME type; falls
/// back to the URL extension; final fallback is generic JPEG (most images
/// from feeds are JPEG and iOS is forgiving about the hint).
private func inferUTType(from response: URLResponse?, fallbackURL: URL) -> UTType {
    if let mime = response?.mimeType, let type = UTType(mimeType: mime) {
        return type
    }
    let ext = fallbackURL.pathExtension.lowercased()
    if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
        return type
    }
    return .jpeg
}
