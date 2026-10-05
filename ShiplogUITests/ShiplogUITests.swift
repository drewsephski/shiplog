import XCTest

@MainActor final class ShiplogUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 15))
        screenshot("Onboarding")
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.buttons["today.logBuild"].waitForExistence(timeout: 5))
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFirstBuildProjectReflectionAndAllTabs() {
        let app = launch()
        screenshot("Today — empty")
        app.buttons["today.logBuild"].tap()
        XCTAssertFalse(app.buttons["entry.save"].isEnabled)
        app.buttons["entry.createProject"].tap()
        app.textFields["project.name"].tap()
        app.textFields["project.name"].typeText("Fieldnotes")
        app.buttons["project.save"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "entry.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Shipped local search")
        let detail = app.descendants(matching: .any).matching(identifier: "entry.detail").firstMatch
        detail.tap()
        detail.typeText("Indexed notes on device. Old ideas are easier to find.")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Shipped local search"))
                .firstMatch.waitForExistence(timeout: 5))
        screenshot("Today — first build")
        app.buttons["today.reflection"].tap()
        app.descendants(matching: .any).matching(identifier: "reflection.text").firstMatch.tap()
        app.descendants(matching: .any).matching(identifier: "reflection.text").firstMatch.typeText(
            "A small feature made the whole app more useful.")
        app.buttons["reflection.save"].tap()
        XCTAssertTrue(app.staticTexts["A small feature made the whole app more useful."].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Shipped local search"))
                .firstMatch.waitForExistence(timeout: 5))
        screenshot("History")
        app.tabBars.buttons["Projects"].tap()
        app.staticTexts["Fieldnotes"].tap()
        XCTAssertTrue(app.staticTexts["The build story"].exists || app.staticTexts["THE BUILD STORY"].exists)
        screenshot("Project detail")
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["day shipping streak"].waitForExistence(timeout: 5))
        screenshot("Insights")
    }

    func testProjectValidationArchiveRestoreAndDelete() {
        let app = launch()
        app.tabBars.buttons["Projects"].tap()
        app.buttons["projects.add"].tap()
        app.textFields["project.name"].tap()
        app.textFields["project.name"].typeText("Wayfinder")
        app.textFields["project.repositoryURL"].tap()
        app.textFields["project.repositoryURL"].typeText("http://example.com/repo")
        app.buttons["project.save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t save"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        let field = app.textFields["project.repositoryURL"]
        field.tap()
        let value = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        field.typeText("https://example.com/repo")
        app.buttons["project.save"].tap()
        XCTAssertTrue(app.staticTexts["Wayfinder"].waitForExistence(timeout: 5))
        app.staticTexts["Wayfinder"].tap()
        app.buttons["Project actions"].tap()
        app.buttons["Archive project"].tap()
        XCTAssertTrue(app.staticTexts["Archived project"].waitForExistence(timeout: 5))
        app.buttons["Project actions"].tap()
        app.buttons["Restore project"].tap()
        app.buttons["Project actions"].tap()
        app.buttons["Delete project"].tap()
        app.buttons["Delete project and entries"].tap()
        XCTAssertTrue(app.staticTexts["Every build has a home."].waitForExistence(timeout: 5))
    }

    func testSettingsExportAndConnectionDisclosure() {
        let app = launch()
        app.buttons["Settings"].tap()
        app.buttons["settings.export"].tap()
        XCTAssertTrue(app.buttons["Share journal export"].waitForExistence(timeout: 5))
        app.staticTexts["GitHub"].tap()
        XCTAssertTrue(app.staticTexts["For now, your journal starts with you."].waitForExistence(timeout: 5))
        screenshot("GitHub — coming later")
    }
}
