import Foundation

// MARK: - Types

/// Result of a feed HTTP fetch, carrying raw data and cache headers.
public struct FeedFetchResult: Sendable {
    public let data: Data
    public let httpStatus: Int
    public let etag: String?
    public let lastModified: String?
    public let wasNotModified: Bool

    public init(
        data: Data,
        httpStatus: Int,
        etag: String? = nil,
        lastModified: String? = nil,
        wasNotModified: Bool = false
    ) {
        self.data = data
        self.httpStatus = httpStatus
        self.etag = etag
        self.lastModified = lastModified
        self.wasNotModified = wasNotModified
    }
}

/// Errors specific to feed fetching.
public enum FeedFetchError: Error, Sendable {
    case invalidURL
    case httpError(statusCode: Int)
    case networkError(underlying: String)
    case timeout
}

// MARK: - Protocol

/// Abstraction for fetching feed data over HTTP.
///
/// The protocol enables injecting a `MockFeedFetcher` in tests while
/// the production implementation uses `URLSession`.
public protocol FeedFetcherProtocol: Sendable {
    func fetch(url: String, etag: String?, lastModified: String?) async throws -> FeedFetchResult
}

// MARK: - URLSession Implementation

/// Production feed fetcher using `URLSession` with conditional-GET support.
public struct URLSessionFeedFetcher: FeedFetcherProtocol, Sendable {
    private let session: URLSession

    public init(timeoutInterval: TimeInterval = 30) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2
        config.httpAdditionalHeaders = [
            "User-Agent": "NebularNews/1.0 (iOS; RSS Reader)"
        ]
        self.session = URLSession(configuration: config)
    }

    public func fetch(url: String, etag: String?, lastModified: String?) async throws -> FeedFetchResult {
        guard let requestURL = URL(string: url) else {
            throw FeedFetchError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        // Conditional-GET headers — server returns 304 if nothing changed
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw FeedFetchError.timeout
        } catch {
            throw FeedFetchError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedFetchError.networkError(underlying: "Non-HTTP response")
        }

        // 304 Not Modified — feed hasn't changed since last poll
        if httpResponse.statusCode == 304 {
            return FeedFetchResult(
                data: Data(),
                httpStatus: 304,
                etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? etag,
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? lastModified,
                wasNotModified: true
            )
        }

        // 4xx/5xx errors
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FeedFetchError.httpError(statusCode: httpResponse.statusCode)
        }

        return FeedFetchResult(
            data: data,
            httpStatus: httpResponse.statusCode,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
            wasNotModified: false
        )
    }
}
