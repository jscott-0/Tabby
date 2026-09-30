import Foundation

public struct ExtractionResult: Sendable {
    public var parsed: ParsedProfileURL
    public var metadata: ProfileMetadata
    public var status: ExtractionStatus
    public var httpStatus: Int?
    public var error: String?
    /// Raw page, kept so the spike CLI can save it as a fixture.
    public var html: String?
}

/// Runs tiers 2–3 for one shared profile: exactly one page request per share
/// (a short link's redirect lands on the profile page, which is reused).
public struct MetadataFetcher: Sendable {
    public let client: any HTTPClient

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    public func fetch(_ parsed: ParsedProfileURL) async -> ExtractionResult {
        var parsed = parsed
        var response: HTTPResponse?
        do {
            if parsed.kind == .shortLink {
                let redirected = try await client.get(parsed.url)
                let resolved = ProfileURLParser.parse(redirected.url)
                if resolved.kind != .shortLink {
                    parsed = resolved
                    response = redirected
                }
            }
            guard parsed.kind == .profile else {
                return failure(parsed, error: "Not a profile URL", httpStatus: response?.statusCode)
            }
            let page: HTTPResponse
            if let response {
                page = response
            } else {
                page = try await client.get(parsed.url)
            }
            let html = String(decoding: page.body, as: UTF8.self)
            guard (200..<300).contains(page.statusCode) else {
                var result = failure(parsed, error: "HTTP \(page.statusCode)", httpStatus: page.statusCode)
                result.html = html
                return result
            }
            let metadata = MetadataExtractor.extract(html: html, platform: parsed.platform)
            return ExtractionResult(
                parsed: parsed, metadata: metadata, status: metadata.status,
                httpStatus: page.statusCode, error: nil, html: html
            )
        } catch {
            return failure(parsed, error: error.localizedDescription, httpStatus: nil)
        }
    }

    private func failure(_ parsed: ParsedProfileURL, error: String, httpStatus: Int?) -> ExtractionResult {
        ExtractionResult(parsed: parsed, metadata: ProfileMetadata(), status: .failed, httpStatus: httpStatus, error: error, html: nil)
    }
}
