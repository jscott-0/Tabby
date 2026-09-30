import Foundation

/// Tier 4: a browser engine that runs the page's scripts. The main app provides one (WebKit);
/// the share extension doesn't, since it's slow and memory-hungry.
public protocol PageRenderer: Sendable {
    /// The page's HTML after its scripts have run.
    func renderedHTML(for url: URL) async throws -> String
}

public struct EnrichmentResult: Sendable {
    public var extraction: ExtractionResult
    /// Downscaled avatar, when one was found and downloaded.
    public var avatarData: Data?
    public var usedRenderedPage: Bool
}

/// Tiers 2–3, then tier 4 if a renderer is available and the result is incomplete, then the avatar.
public struct EnrichmentService: Sendable {
    public let client: any HTTPClient
    public let renderer: (any PageRenderer)?

    public init(client: any HTTPClient = URLSessionHTTPClient(), renderer: (any PageRenderer)? = nil) {
        self.client = client
        self.renderer = renderer
    }

    public var fetcher: MetadataFetcher { MetadataFetcher(client: client) }

    public func enrich(_ parsed: ParsedProfileURL, downloadAvatar: Bool = true) async -> EnrichmentResult {
        var extraction = await fetcher.fetch(parsed)
        var usedRenderedPage = false

        if extraction.status != .complete, let renderer, extraction.parsed.kind == .profile,
           let html = try? await renderer.renderedHTML(for: extraction.parsed.url) {
            var metadata = extraction.metadata
            metadata.merge(MetadataExtractor.extract(html: html, platform: extraction.parsed.platform), tier: .renderedPage)
            if metadata.status.rank > extraction.status.rank {
                extraction.metadata = metadata
                extraction.status = metadata.status
                extraction.error = nil
                usedRenderedPage = true
            }
        }

        var avatarData: Data?
        if downloadAvatar, let avatarURL = extraction.metadata.avatarURL {
            avatarData = await AvatarProcessor.download(avatarURL, client: client)
        }
        return EnrichmentResult(extraction: extraction, avatarData: avatarData, usedRenderedPage: usedRenderedPage)
    }
}
