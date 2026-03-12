import Foundation

public func canonicalFeedURLForStorage(_ rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard var components = URLComponents(string: candidate),
          let host = components.host?.lowercased()
    else {
        return nil
    }

    let scheme = (components.scheme ?? "https").lowercased()
    components.scheme = scheme == "http" ? "https" : scheme
    components.host = host
    components.fragment = nil

    if let port = components.port {
        if (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }
    }

    var path = components.percentEncodedPath
    if path.isEmpty {
        path = "/"
    }
    if path != "/" {
        path = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    if host == "feeds.pbs.org", path.hasPrefix("/newshour/rss/") {
        components.host = "pbs.org"
        path = "/newshour/feeds/rss/" + String(path.dropFirst("/newshour/rss/".count))
    }

    components.percentEncodedPath = path
    return components.string
}
