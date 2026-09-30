import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import TabbyKit

/// Returns fixed HTML, as if scripts had run in a browser.
private struct StubRenderer: PageRenderer {
    let html: String
    func renderedHTML(for url: URL) async throws -> String { html }
}

@MainActor
final class EnrichmentTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try TabbyContainer.make(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private static func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private static func pixelSize(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private let profile = ProfileURLParser.profile(platform: .tiktok, handle: "tabby_sample_dev")!
    private let avatarURL = "https://cdn.example.com/tt/dev.jpg"
    private var pageHTML: String {
        """
        <meta property="og:title" content="Dev Okafor (@tabby_sample_dev) | TikTok">
        <meta property="og:image" content="\(avatarURL)">
        <meta property="og:description" content="Dev Okafor (@tabby_sample_dev) on TikTok | 10 Likes. 5 Followers. hardware tinkerer. Watch the latest video from Dev Okafor (@tabby_sample_dev).">
        """
    }

    // MARK: Avatars

    func testAvatarIsDownscaledTo400Pixels() throws {
        let jpeg = try XCTUnwrap(AvatarProcessor.downscaledJPEG(Self.pngData(width: 1200, height: 800)))
        let (width, height) = try XCTUnwrap(Self.pixelSize(of: jpeg))
        XCTAssertEqual(max(width, height), 400)
        XCTAssertEqual(width, 400)
        XCTAssertNil(AvatarProcessor.downscaledJPEG(Data("not an image".utf8)))
    }

    // MARK: Enrichment service

    func testEnrichFetchesPageAndAvatar() async throws {
        let client = StubHTTPClient([
            profile.url.absoluteString: HTTPResponse(url: profile.url, statusCode: 200, body: Data(pageHTML.utf8)),
            avatarURL: HTTPResponse(url: URL(string: avatarURL)!, statusCode: 200, body: Self.pngData(width: 800, height: 800)),
        ])
        let result = await EnrichmentService(client: client).enrich(profile)
        XCTAssertEqual(result.extraction.status, .complete)
        XCTAssertFalse(result.usedRenderedPage)
        let avatar = try XCTUnwrap(result.avatarData)
        XCTAssertEqual(Self.pixelSize(of: avatar)?.0, 400)
    }

    func testRenderedPageFillsInWhenFetchFails() async {
        let renderer = StubRenderer(html: pageHTML)
        let result = await EnrichmentService(client: StubHTTPClient([:]), renderer: renderer).enrich(profile, downloadAvatar: false)
        XCTAssertTrue(result.usedRenderedPage)
        XCTAssertEqual(result.extraction.status, .complete)
        XCTAssertEqual(result.extraction.metadata.name, "Dev Okafor")
        XCTAssertEqual(result.extraction.metadata.sources[.name], .renderedPage)
    }

    func testRendererIsSkippedWhenFetchIsComplete() async {
        let client = StubHTTPClient([
            profile.url.absoluteString: HTTPResponse(url: profile.url, statusCode: 200, body: Data(pageHTML.utf8)),
        ])
        let renderer = StubRenderer(html: "<title>should not be used</title>")
        let result = await EnrichmentService(client: client, renderer: renderer).enrich(profile, downloadAvatar: false)
        XCTAssertFalse(result.usedRenderedPage)
    }

    // MARK: Retry queue

    func testFailedShareRecoversOnRetry() async throws {
        let context = try makeContext()
        let store = TabbyStore(context: context)
        var draft = PersonDraft(parsed: profile)
        draft.extractionStatus = .failed
        let person = try store.save(draft).person
        XCTAssertTrue(person.needsInfo)

        let client = StubHTTPClient([
            profile.url.absoluteString: HTTPResponse(url: profile.url, statusCode: 200, body: Data(pageHTML.utf8)),
            avatarURL: HTTPResponse(url: URL(string: avatarURL)!, statusCode: 200, body: Self.pngData(width: 600, height: 600)),
        ])
        let queue = RetryQueue(context: context, service: EnrichmentService(client: client), log: nil)
        let retried = await queue.run()

        XCTAssertEqual(retried, 1)
        XCTAssertFalse(person.needsInfo)
        XCTAssertEqual(person.displayName, "Dev Okafor")
        XCTAssertNotNil(person.avatarData)
        XCTAssertEqual(person.primaryAccount?.extractionStatus, .complete)
        XCTAssertEqual(person.primaryAccount?.fetchAttempts, 1)
        XCTAssertTrue(queue.candidates().isEmpty, "complete profiles are never retried")
    }

    func testRetriesBackOffAndStop() async throws {
        let context = try makeContext()
        let store = TabbyStore(context: context)
        var draft = PersonDraft(parsed: profile)
        draft.extractionStatus = .failed
        let account = try XCTUnwrap(try store.save(draft).person.primaryAccount)
        let queue = RetryQueue(context: context, service: EnrichmentService(client: StubHTTPClient([:])), log: nil)
        let start = Date.now

        await queue.run(now: start)
        XCTAssertEqual(account.fetchAttempts, 1)
        XCTAssertTrue(queue.candidates(now: start.addingTimeInterval(60)).isEmpty, "waits between attempts")

        await queue.run(now: start.addingTimeInterval(2 * RetryQueue.minimumInterval))
        await queue.run(now: start.addingTimeInterval(4 * RetryQueue.minimumInterval))
        XCTAssertEqual(account.fetchAttempts, RetryQueue.maxAttempts)
        XCTAssertTrue(queue.candidates(now: start.addingTimeInterval(10 * RetryQueue.minimumInterval)).isEmpty, "gives up")
        XCTAssertEqual(account.person?.needsInfo, true, "still shown in Needs info")
    }

    func testUserEditsSurviveEnrichmentButRefetchOverwrites() throws {
        let context = try makeContext()
        let store = TabbyStore(context: context)
        var draft = PersonDraft(parsed: profile)
        draft.displayName = "Dev (the PCB guy)"
        draft.bio = "my own summary"
        let person = try store.save(draft).person
        let account = try XCTUnwrap(person.primaryAccount)
        account.fetchAttempts = 2

        var metadata = ProfileMetadata()
        metadata.name = "Dev Okafor"
        metadata.bio = "hardware tinkerer"
        let result = EnrichmentResult(
            extraction: ExtractionResult(parsed: profile, metadata: metadata, status: .partial, httpStatus: 200, error: nil, html: nil),
            avatarData: nil, usedRenderedPage: false
        )

        store.applyEnrichment(result, to: account)
        XCTAssertEqual(person.displayName, "Dev (the PCB guy)")
        XCTAssertEqual(account.bio, "my own summary")

        store.applyEnrichment(result, to: account, overwrite: true)
        XCTAssertEqual(person.displayName, "Dev (the PCB guy)", "a re-fetch never renames")
        XCTAssertEqual(account.bio, "hardware tinkerer")
        XCTAssertEqual(account.fetchAttempts, 0, "a re-fetch resets automatic retries")
    }

    // MARK: Extraction log

    func testLogKeepsNewestFirstAndComputesHitRates() {
        let log = ExtractionLog(defaults: UserDefaults(suiteName: "tabby-log-\(UUID().uuidString)")!)
        var complete = ProfileMetadata()
        complete.name = "Dev"
        complete.bio = "bio"
        complete.avatarURL = URL(string: avatarURL)
        complete.sources = [.name: .metaTags, .bio: .embeddedJSON, .avatarURL: .metaTags]
        let linkedIn = ProfileURLParser.profile(platform: .linkedin, handle: "tabby-sample-priya")!

        log.append(ExtractionAttempt(ExtractionResult(parsed: profile, metadata: complete, status: .complete, httpStatus: 200, error: nil, html: nil), source: .shareSheet))
        log.append(ExtractionAttempt(ExtractionResult(parsed: linkedIn, metadata: ProfileMetadata(), status: .failed, httpStatus: 999, error: "HTTP 999", html: nil), source: .shareSheet))

        XCTAssertEqual(log.attempts.map(\.platform), [.linkedin, .tiktok])
        let rows = ExtractionStats.rows(log.attempts)
        let tiktok = try? XCTUnwrap(rows.first { $0.platform == .tiktok })
        XCTAssertEqual(tiktok?.fieldRates[.name], 1)
        XCTAssertEqual(tiktok?.fieldRates[.headline], 0)
        XCTAssertEqual(rows.first { $0.platform == .linkedin }?.statusRates[.failed], 1)
        XCTAssertTrue(ExtractionStats.markdownTable(log.attempts).contains("| tiktok | 1 | 100% | 0% | 100% | 100% | 0% | 0% | 100% | 0% | 0% |"))

        log.clear()
        XCTAssertTrue(log.attempts.isEmpty)
    }
}
