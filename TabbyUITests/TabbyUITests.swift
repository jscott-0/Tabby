import XCTest

/// Smoke tests on the simulator: the app launches with the sample data (in memory, offline),
/// the main screens render, and the share sheet saves. Screenshots are attached to the result
/// bundle; CI exports them.
final class TabbyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extraArguments
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSpacesToSpaceToPerson() {
        let app = launch()
        let tile = element("space-tile-Hardware designers", in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        screenshot("01-spaces", app)

        tile.tap()
        let priya = element("person-row-Priya Castellan", in: app)
        XCTAssertTrue(priya.waitForExistence(timeout: 5))
        XCTAssertFalse(element("person-row-Mara Quill", in: app).exists, "ALL of designer + hardware excludes designer-only people")
        screenshot("02-space-detail", app)

        priya.tap()
        XCTAssertTrue(app.buttons["Open in app"].waitForExistence(timeout: 5))
        screenshot("03-person-detail", app)
    }

    func testSearchFindsByTagAndBio() {
        let app = launch()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 20))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ceramic")
        XCTAssertTrue(element("person-row-Aiko Lindqvist", in: app).waitForExistence(timeout: 5))
        screenshot("04-search", app)
    }

    func testTagsScreen() {
        let app = launch()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 20))
        app.buttons["Tags"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["designer"].waitForExistence(timeout: 5))
        screenshot("05-tags", app)
    }

    func testCreateSpace() {
        let app = launch()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 20))
        app.buttons["Add"].firstMatch.tap()
        app.buttons["New Space"].firstMatch.tap()
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Food people")
        app.buttons["food"].firstMatch.tap()
        screenshot("06-space-editor", app)
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(element("space-tile-Food people", in: app).waitForExistence(timeout: 5))
    }

    func testAddPersonFromPastedLink() {
        let app = launch()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 20))
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Add person"].firstMatch.tap()
        let link = element("add-link", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://www.tiktok.com/@tabby_new_person")
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let filled = expectation(for: NSPredicate(format: "value == %@", "Sample Person"), evaluatedWith: name)
        wait(for: [filled], timeout: 10)
        screenshot("07-add-person", app)
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 5))
    }

    func testShareSheetSavesProfile() {
        let app = launch(["-uiTestingShare", "https://www.tiktok.com/@tabby_shared?_t=8abc"])
        let save = element("share-save", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        let name = element("preview-name", in: app)
        let filled = expectation(for: NSPredicate(format: "value == %@", "Sample Person"), evaluatedWith: name)
        wait(for: [filled], timeout: 10)
        screenshot("08-share-sheet", app)

        save.tap()
        XCTAssertTrue(app.staticTexts["Saved to Tabby!"].waitForExistence(timeout: 5))
        screenshot("09-saved", app)
    }

    func testShareSheetForAPost() {
        let app = launch(["-uiTestingShare", "https://www.instagram.com/reel/C1a2b3c4/"])
        XCTAssertTrue(element("share-save", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["This looks like a post, not a profile. It will be saved as a link."].waitForExistence(timeout: 5))
        screenshot("10-share-post", app)
    }
}
