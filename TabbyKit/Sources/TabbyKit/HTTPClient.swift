import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    /// Final URL after redirects.
    public var url: URL
    public var statusCode: Int
    public var body: Data

    public init(url: URL, statusCode: Int, body: Data) {
        self.url = url
        self.statusCode = statusCode
        self.body = body
    }
}

/// Network boundary, so parsers and the fetcher can be tested with stubs.
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    public static let mobileSafariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    /// `timeout` bounds the whole request, redirects included.
    public init(timeout: TimeInterval = 8) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.setValue(Self.mobileSafariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return HTTPResponse(url: http?.url ?? url, statusCode: http?.statusCode ?? 0, body: data)
    }
}
