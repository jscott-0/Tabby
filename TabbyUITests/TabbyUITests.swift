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

    // MARK: Onboarding and paywall

    /// Scrolls until the element can be tapped (Form rows below the fold aren't).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    func testOnboardingToFirstSaveThenPaywallAndDemo() {
        let app = launch(["-uiTestingOnboarding"])
        let next = element("onboarding-continue", in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        screenshot("11-onboarding-welcome", app)
        next.tap()

        let email = element("onboarding-email", in: app)
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        screenshot("12-onboarding-account", app)
        email.tap()
        email.typeText("sample@example.com")
        next.tap()

        let food = element("interest-food", in: app)
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        let creator = element("creator-instagram:tastemade", in: app)
        XCTAssertTrue(creator.waitForExistence(timeout: 5))
        creator.tap()
        screenshot("13-onboarding-interests", app)
        next.tap()

        let pasteLink = element("onboarding-paste-link", in: app)
        XCTAssertTrue(pasteLink.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open @tastemade in Instagram"].exists)
        screenshot("14-onboarding-first-suggestion", app)
        pasteLink.tap()

        let link = element("add-link", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://www.tiktok.com/@tabby_first_save")
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Sample Person"), evaluatedWith: name)], timeout: 10)
        app.buttons["Save"].firstMatch.tap()

        // Onboarding ends on the saved person, then the paywall.
        let title = element("paywall-title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Your first Tab is saved!")
        screenshot("15-paywall-first-save", app)

        element("paywall-demo", in: app).tap()
        XCTAssertTrue(element("demo-banner", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("space-tile-Hardware designers", in: app).waitForExistence(timeout: 5))
        screenshot("16-demo", app)

        element("demo-exit", in: app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10), "leaving the demo returns to the paywall")
        element("paywall-option-unlimited", in: app).tap()
        element("paywall-buy", in: app).tap()
        XCTAssertTrue(element("space-tile-All", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("free-plan-banner", in: app).exists, "unlocked")
        XCTAssertFalse(element("space-tile-Hardware designers", in: app).exists, "demo data is gone")
    }

    func testFreePlanSavesLockedDraft() {
        let app = launch(["-uiTestingFree"])
        let banner = element("free-plan-banner", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 20))
        screenshot("17-free-plan-banner", app)

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Add person"].firstMatch.tap()
        let link = element("add-link", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://www.tiktok.com/@tabby_locked_person")
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Sample Person"), evaluatedWith: name)], timeout: 10)
        app.buttons["Save draft"].firstMatch.tap()

        let title = element("paywall-title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Saved as a draft")
        screenshot("18-paywall-slot-limit", app)
        element("paywall-close", in: app).tap()

        let waiting = element("space-tile-Waiting to unlock", in: app)
        XCTAssertTrue(waiting.waitForExistence(timeout: 5))
        waiting.tap()
        let row = element("person-row-Sample Person", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        screenshot("19-waiting-to-unlock", app)
        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "a locked draft opens the paywall")
    }

    func testShareSheetTeachingMode() {
        let app = launch(["-uiTestingTeaching", "-uiTestingShare", "https://www.tiktok.com/@tabby_teaching"])
        let save = element("share-save", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        XCTAssertEqual(save.label, "Import")
        XCTAssertFalse(save.isEnabled, "the checklist comes first")
        let name = element("preview-name", in: app)
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Sample Person"), evaluatedWith: name)], timeout: 10)
        screenshot("20-share-teaching", app)

        element("share-confirm-details", in: app).tap()
        let tag = app.buttons["designer"].firstMatch
        reveal(tag, in: app)
        tag.tap()
        let note = element("share-note", in: app)
        reveal(note, in: app)
        note.tap()
        note.typeText("Great packaging work")
        XCTAssertTrue(save.isEnabled)
        screenshot("21-share-teaching-done", app)
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved to Tabby!"].waitForExistence(timeout: 5))
    }
}
