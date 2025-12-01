import XCTest

final class WareHouse_AppUITests: XCTestCase {
    func testSupplyFormValidationShowsErrors() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSampleData")
        app.launch()

        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let supplyButton = app.buttons["supplySubmitButton"]
        XCTAssertTrue(supplyButton.waitForExistence(timeout: 5))
        supplyButton.click()

        let errorText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "тов")).firstMatch
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))
    }

    func testAnalysisTabShowsStatuses() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSampleData")
        app.launch()

        app.tabGroups.buttons["Анализ сети"].click()
        let runButton = app.buttons["runAnalysisButton"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "проблем")).firstMatch.exists)
    }

    func testTransferFlowRequiresValidInput() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSampleData")
        app.launch()

        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            scrollView.swipeUp()
        }

        let picker = app.popUpButtons["Целевой склад"]
        XCTAssertTrue(picker.waitForExistence(timeout: 2))
        picker.click()
        app.menuItems["Secondary"].click()

        let submit = app.buttons["transferSubmitButton"]
        XCTAssertTrue(submit.waitForExistence(timeout: 2))
        submit.click()

        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Количество")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 2))
    }
}
