import Foundation
import CryptoKit

func normalizedCanonicalArticleURL(from value: String?) -> String? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawValue.isEmpty,
          var components = URLComponents(string: rawValue),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased()
    else {
        return nil
    }

    components.scheme = scheme
    components.host = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    components.fragment = nil
    components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

    if components.path.isEmpty {
        components.path = "/"
    }

    return components.string?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func standaloneArticleKey(
    canonicalURL: String?,
    feedKey: String?,
    title: String?,
    publishedAt: Date?
) -> String? {
    if let normalizedURL = normalizedCanonicalArticleURL(from: canonicalURL) {
        return normalizedURL
    }

    let normalizedTitle = title?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    guard let feedKey, !feedKey.isEmpty,
          let normalizedTitle, !normalizedTitle.isEmpty
    else {
        return nil
    }

    let publishedComponent = publishedAt.map(standaloneArticleKeyPublishedComponent) ?? "undated"

    let base = "\(feedKey)|\(publishedComponent)|\(normalizedTitle)"
    let digest = SHA256.hash(data: Data(base.utf8))
    let hash = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    return "derived:\(hash)"
}

private func standaloneArticleKeyPublishedComponent(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
