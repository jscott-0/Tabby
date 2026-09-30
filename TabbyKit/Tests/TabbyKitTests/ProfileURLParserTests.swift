import XCTest
@testable import TabbyKit

final class ProfileURLParserTests: XCTestCase {
    private func parse(_ string: String) -> ParsedProfileURL {
        ProfileURLParser.parse(URL(string: string)!)
    }

    // MARK: LinkedIn

    func testLinkedInProfileVariants() {
        for string in [
            "https://www.linkedin.com/in/priya-castellan",
            "https://linkedin.com/in/priya-castellan/",
            "https://www.linkedin.com/in/priya-castellan?utm_source=share&utm_medium=member_ios",
            "https://uk.linkedin.com/in/priya-castellan",
        ] {
            let parsed = parse(string)
            XCTAssertEqual(parsed.platform, .linkedin, string)
            XCTAssertEqual(parsed.kind, .profile, string)
            XCTAssertEqual(parsed.handle, "priya-castellan", string)
            XCTAssertEqual(parsed.url.absoluteString, "https://www.linkedin.com/in/priya-castellan/", string)
        }
    }

    func testLinkedInPostDetectsAuthor() {
        let parsed = parse("https://www.linkedin.com/posts/priya-castellan_hardware-design-activity-7123456789")
        XCTAssertEqual(parsed.kind, .post(authorHandle: "priya-castellan"))
        XCTAssertNil(parsed.handle)
        XCTAssertEqual(parsed.authorProfile?.handle, "priya-castellan")
    }

    // MARK: Instagram

    func testInstagramProfileStripsQueryAndLowercases() {
        let parsed = parse("https://www.instagram.com/Mara.Quill.Studio/?igsh=MWx0b2F4&utm_source=qr")
        XCTAssertEqual(parsed.platform, .instagram)
        XCTAssertEqual(parsed.kind, .profile)
        XCTAssertEqual(parsed.handle, "mara.quill.studio")
        XCTAssertEqual(parsed.url.absoluteString, "https://www.instagram.com/mara.quill.studio/")
        XCTAssertEqual(parsed.dedupKey, "instagram:mara.quill.studio")
    }

    func testInstagramReservedPathsAreNotProfiles() {
        XCTAssertEqual(parse("https://www.instagram.com/p/C1a2b3c4/").kind, .post(authorHandle: nil))
        XCTAssertEqual(parse("https://www.instagram.com/reel/C1a2b3c4/?igsh=abc").kind, .post(authorHandle: nil))
        XCTAssertEqual(parse("https://www.instagram.com/explore/").kind, .unknown)
        XCTAssertEqual(parse("https://www.instagram.com/stories/mara.quill.studio/3141592/").kind,
                       .post(authorHandle: "mara.quill.studio"))
        XCTAssertEqual(parse("https://www.instagram.com/stories/highlights/1234/").kind, .post(authorHandle: nil))
    }

    func testInstagramPostWithAuthorPrefix() {
        let parsed = parse("https://www.instagram.com/mara.quill.studio/p/C1a2b3c4/")
        XCTAssertEqual(parsed.kind, .post(authorHandle: "mara.quill.studio"))
    }

    // MARK: TikTok

    func testTikTokProfile() {
        let parsed = parse("https://www.tiktok.com/@DevBuilds?_t=8abc&_r=1")
        XCTAssertEqual(parsed.platform, .tiktok)
        XCTAssertEqual(parsed.kind, .profile)
        XCTAssertEqual(parsed.handle, "devbuilds")
        XCTAssertEqual(parsed.url.absoluteString, "https://www.tiktok.com/@devbuilds")
    }

    func testTikTokVideoDetectsAuthor() {
        XCTAssertEqual(parse("https://www.tiktok.com/@devbuilds/video/7300000000000000000").kind,
                       .post(authorHandle: "devbuilds"))
    }

    func testTikTokShortLinks() {
        XCTAssertEqual(parse("https://vm.tiktok.com/ZMabc123/").kind, .shortLink)
        XCTAssertEqual(parse("https://www.tiktok.com/t/ZTabc123/").kind, .shortLink)
    }

    // MARK: Other / text

    func testOtherHost() {
        let parsed = parse("https://priya.example.com/work")
        XCTAssertEqual(parsed.platform, .other)
        XCTAssertEqual(parsed.kind, .unknown)
    }

    func testFirstURLInSharedText() {
        let url = ProfileURLParser.firstURL(in: "Check out Dev Okafor's profile on TikTok! https://www.tiktok.com/@devbuilds?_t=8abc")
        XCTAssertEqual(url?.host, "www.tiktok.com")
        XCTAssertEqual(ProfileURLParser.firstURL(in: "  https://www.instagram.com/leo.makes/  ")?.absoluteString, "https://www.instagram.com/leo.makes/")
        XCTAssertNil(ProfileURLParser.firstURL(in: "no links here"))
    }
}
