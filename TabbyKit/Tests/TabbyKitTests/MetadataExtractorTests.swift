import XCTest
@testable import TabbyKit

final class MetadataExtractorTests: XCTestCase {
    private func fixture(_ path: String) throws -> String {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testInstagramWithEmbeddedJSON() throws {
        let metadata = MetadataExtractor.extract(html: try fixture("instagram/synthetic_profile.html"), platform: .instagram)
        XCTAssertEqual(metadata.name, "Mara Quill")
        XCTAssertEqual(metadata.avatarURL?.absoluteString, "https://cdn.example.com/ig/mara.jpg")
        XCTAssertEqual(metadata.followerCount, 12431)
        XCTAssertEqual(metadata.sources[.followerCount], .embeddedJSON)
        XCTAssertEqual(metadata.bio?.hasPrefix("Packaging designer • Portland\n"), true)
        XCTAssertEqual(metadata.sources[.bio], .embeddedJSON)
        XCTAssertEqual(metadata.links.map { $0.host }, ["maraquill.example.com"])
        XCTAssertEqual(metadata.emails, ["hello@maraquill.example.com"])
        XCTAssertEqual(metadata.status, .complete)
    }

    func testInstagramMetaTagsOnly() throws {
        let metadata = MetadataExtractor.extract(html: try fixture("instagram/synthetic_meta_only.html"), platform: .instagram)
        XCTAssertEqual(metadata.name, "Leo Brandt")
        XCTAssertEqual(metadata.followerCount, 1204)
        XCTAssertEqual(metadata.bio, "Furniture maker. Commissions open.")
        XCTAssertEqual(metadata.sources[.bio], .metaTags)
        XCTAssertEqual(metadata.status, .complete)
    }

    func testTikTokPrefersEmbeddedJSON() throws {
        let metadata = MetadataExtractor.extract(html: try fixture("tiktok/synthetic_profile.html"), platform: .tiktok)
        XCTAssertEqual(metadata.name, "Dev Okafor")
        XCTAssertEqual(metadata.bio, "hardware tinkerer 🔧\nbuilds.example.com")
        XCTAssertEqual(metadata.followerCount, 48512)
        XCTAssertEqual(metadata.links.map { $0.host }, ["builds.example.com"])
        XCTAssertNotNil(metadata.avatarURL)
        XCTAssertEqual(metadata.status, .complete)
    }

    func testTikTokMetaTier() throws {
        let metadata = MetadataExtractor.metaTags(try fixture("tiktok/synthetic_profile.html"), .tiktok)
        XCTAssertEqual(metadata.followerCount, 48500)
        XCTAssertEqual(metadata.bio, "hardware tinkerer.")
    }

    func testLinkedInTitleAndJSONLD() throws {
        let metadata = MetadataExtractor.extract(html: try fixture("linkedin/synthetic_profile.html"), platform: .linkedin)
        XCTAssertEqual(metadata.name, "Priya Castellan")
        XCTAssertEqual(metadata.headline, "Industrial Designer · Northwind Labs")
        XCTAssertEqual(metadata.bio, "I design hardware that ships. Portfolio: priya.example.com")
        XCTAssertEqual(metadata.links.map { $0.host }, ["priya.example.com"])
        XCTAssertEqual(metadata.status, .complete)
    }

    func testLinkedInLoginWallYieldsNothing() throws {
        let metadata = MetadataExtractor.extract(html: try fixture("linkedin/synthetic_authwall.html"), platform: .linkedin)
        XCTAssertNil(metadata.name)
        XCTAssertNil(metadata.avatarURL)
        XCTAssertNil(metadata.bio)
        XCTAssertEqual(metadata.status, .failed)
    }

    func testHTMLEntities() {
        XCTAssertEqual(HTMLEntities.decode("A &amp; B &#x2022; &#183; &quot;q&quot; &bogus;"), "A & B • · \"q\" &bogus;")
    }
}
