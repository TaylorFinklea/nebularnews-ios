import Foundation

struct UnsplashSearchPhoto: Sendable {
    let imageUrl: String
    let photographerName: String
    let photographerProfileUrl: String?
    let photoPageUrl: String?
    let downloadLocation: String?
}

actor UnsplashClient {
    private let accessKey: String
    private let session: URLSession
    private let utmSource = "nebularnews_ios"
    private let utmMedium = "referral"

    init(accessKey: String, session: URLSession = .shared) {
        self.accessKey = accessKey
        self.session = session
    }

    func searchPhoto(query: String) async throws -> UnsplashSearchPhoto? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var components = URLComponents(string: "https://api.unsplash.com/search/photos")
        components?.queryItems = [
            .init(name: "query", value: query),
            .init(name: "orientation", value: "landscape"),
            .init(name: "content_filter", value: "high"),
            .init(name: "per_page", value: "10"),
            .init(name: "order_by", value: "relevant")
        ]

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            return nil
        }

        let payload = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
        guard let result = payload.results.first else {
            return nil
        }

        return UnsplashSearchPhoto(
            imageUrl: result.urls.regular,
            photographerName: result.user.name,
            photographerProfileUrl: appendUTM(to: result.user.links.html),
            photoPageUrl: appendUTM(to: result.links.html),
            downloadLocation: result.links.downloadLocation
        )
    }

    func trackDownload(_ downloadLocation: String?) async {
        guard let downloadLocation,
              let url = URL(string: downloadLocation)
        else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        _ = try? await session.data(for: request)
    }

    private func appendUTM(to value: String?) -> String? {
        guard let value,
              var components = URLComponents(string: value)
        else {
            return value
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "utm_source" || $0.name == "utm_medium" }
        items.append(.init(name: "utm_source", value: utmSource))
        items.append(.init(name: "utm_medium", value: utmMedium))
        components.queryItems = items
        return components.url?.absoluteString ?? value
    }
}

private struct UnsplashSearchResponse: Decodable {
    let results: [UnsplashPhotoResult]
}

private struct UnsplashPhotoResult: Decodable {
    let urls: UnsplashPhotoURLs
    let user: UnsplashPhotoUser
    let links: UnsplashPhotoLinks
}

private struct UnsplashPhotoURLs: Decodable {
    let regular: String
}

private struct UnsplashPhotoUser: Decodable {
    let name: String
    let links: UnsplashUserLinks
}

private struct UnsplashUserLinks: Decodable {
    let html: String?
}

private struct UnsplashPhotoLinks: Decodable {
    let html: String?
    let downloadLocation: String?

    private enum CodingKeys: String, CodingKey {
        case html
        case downloadLocation = "download_location"
    }
}
