import XCTest
@testable import TabbyKit

final class BioParserTests: XCTestCase {
    func testLinksAndEmails() {
        let bio = "Designer. Work: priya.example.com | shop https://shop.example.com/p?x=1 — hi@priya.example.com"
        XCTAssertEqual(BioParser.links(in: bio).map { $0.host }, ["priya.example.com", "shop.example.com"])
        XCTAssertEqual(BioParser.emails(in: bio), ["hi@priya.example.com"])
    }

    func testLinkedInTitle() {
        let parsed = BioParser.parseLinkedInTitle("Priya Castellan - Industrial Designer - Northwind Labs | LinkedIn")
        XCTAssertEqual(parsed?.name, "Priya Castellan")
        XCTAssertEqual(parsed?.headline, "Industrial Designer · Northwind Labs")

        let nameOnly = BioParser.parseLinkedInTitle("Priya Castellan | LinkedIn")
        XCTAssertEqual(nameOnly?.name, "Priya Castellan")
        XCTAssertNil(nameOnly?.headline)

        XCTAssertNil(BioParser.parseLinkedInTitle("Sign Up | LinkedIn"))
        XCTAssertNil(BioParser.parseLinkedInTitle("LinkedIn"))
    }

    func testNameBeforeHandle() {
        XCTAssertEqual(BioParser.nameBeforeHandle("Dev Okafor (@devbuilds) | TikTok"), "Dev Okafor")
        XCTAssertNil(BioParser.nameBeforeHandle("(@devbuilds) | TikTok"))
        XCTAssertNil(BioParser.nameBeforeHandle("TikTok - Make Your Day"))
    }

    func testParseCount() {
        XCTAssertEqual(BioParser.parseCount("1,234"), 1234)
        XCTAssertEqual(BioParser.parseCount("12.4K"), 12400)
        XCTAssertEqual(BioParser.parseCount("1.2M"), 1_200_000)
        XCTAssertEqual(BioParser.parseCount("3b"), 3_000_000_000)
        XCTAssertNil(BioParser.parseCount("lots"))
    }
}
