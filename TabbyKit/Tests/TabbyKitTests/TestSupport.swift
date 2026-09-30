import Foundation
@testable import TabbyKit

/// Serves canned responses keyed by requested URL and records every request.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [String: HTTPResponse]
    private var _requests: [URL] = []

    init(_ responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    var requests: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func get(_ url: URL) async throws -> HTTPResponse {
        record(url)
        guard let response = responses[url.absoluteString] else { throw URLError(.notConnectedToInternet) }
        return response
    }

    private func record(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(url)
    }
}
