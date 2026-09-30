import XCTest
@testable import TabbyKit

final class MetadataFetcherTests: XCTestCase {
    private let tiktokHTML = """
    <meta property="og:title" content="Dev Okafor (@devbuilds) | TikTok">
    <meta property="og:image" content="https://cdn.example.com/tt/dev.jpg">
    <meta property="og:description" content="Dev Okafor (@devbuilds) on TikTok | 10 Likes. 5 Followers. hi. Watch the latest video from Dev Okafor (@devbuilds).">
    """

    func testShortLinkReusesRedirectedPage() async throws {
        let shortURL = "https://vm.tiktok.com/ZMabc123/"
        let client = StubHTTPClient([
            shortURL: HTTPResponse(
                url: URL(string: "https://www.tiktok.com/@devbuilds?_t=8abc")!,
                statusCode: 200,
                body: Data(tiktokHTML.utf8)
            ),
        ])
        let result = await MetadataFetcher(client: client).fetch(ProfileURLParser.parse(URL(string: shortURL)!))
        XCTAssertEqual(result.parsed.handle, "devbuilds")
        XCTAssertEqual(result.parsed.kind, .profile)
        XCTAssertEqual(result.metadata.name, "Dev Okafor")
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(client.requests.count, 1, "one request per share")
    }

    func testLinkedIn999IsFailedWithStatus() async {
        let profile = "https://www.linkedin.com/in/priya-castellan/"
        let client = StubHTTPClient([
            profile: HTTPResponse(url: URL(string: profile)!, statusCode: 999, body: Data()),
        ])
        let result = await MetadataFetcher(client: client).fetch(ProfileURLParser.parse(URL(string: profile)!))
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.httpStatus, 999)
        XCTAssertEqual(result.parsed.handle, "priya-castellan", "tier 1 survives a failed fetch")
    }

    func testOfflineFailsButKeepsTier1() async {
        let client = StubHTTPClient([:])
        let result = await MetadataFetcher(client: client).fetch(ProfileURLParser.parse(URL(string: "https://www.instagram.com/leo.makes/")!))
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.parsed.dedupKey, "instagram:leo.makes")
        XCTAssertNotNil(result.error)
    }

    func testPostIsNotFetched() async {
        let client = StubHTTPClient([:])
        let result = await MetadataFetcher(client: client).fetch(ProfileURLParser.parse(URL(string: "https://www.instagram.com/p/C1a2b3c4/")!))
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(client.requests.isEmpty)
    }
}
