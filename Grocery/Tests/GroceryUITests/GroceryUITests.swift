import XCTest

/// Smoke tests for the screens: launch, add, check off, undo, every menu screen, and a recipe import.
/// The app runs with -ui-testing, so it starts from the sample list in a throwaway folder.
final class GroceryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 20), "the list screen opens")
    }

    private func item(_ name: String) -> XCUIElement {
        app.buttons["item-\(name)"]
    }

    /// The row's label changes after the check-off animation, so wait for it rather than reading it at once.
    private func waitFor(_ element: XCUIElement, labelEndingWith suffix: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label ENDSWITH %@", suffix)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func dismissSheet(file: StaticString = #filePath, line: UInt = #line) {
        for name in ["Done", "Close", "Cancel"] {
            let button = app.navigationBars.buttons[name].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 10), "back on the list", file: file, line: line)
                return
            }
        }
        XCTFail("no Done, Close or Cancel button to close the sheet", file: file, line: line)
    }

    func testLaunchShowsTheSampleListAndStores() {
        XCTAssertTrue(item("Bananas").exists)
        XCTAssertTrue(item("Milk").exists)
        XCTAssertTrue(item("Sourdough").exists)
        for store in ["All", "Any Store", "Kroger", "Walmart"] {
            XCTAssertTrue(app.buttons[store].exists, "\(store) chip")
        }
    }

    func testQuickAddTurnsAListIntoItems() {
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("eggs, 2 limes")
        app.buttons["Add items"].tap()
        XCTAssertTrue(item("Eggs").waitForExistence(timeout: 5))
        XCTAssertTrue(item("Limes").exists)
        XCTAssertTrue(item("Limes").label.contains("quantity 2"), item("Limes").label)
    }

    func testCheckingOffClearingAndUndo() {
        let milk = item("Milk")
        milk.tap()
        XCTAssertTrue(waitFor(milk, labelEndingWith: "bought"), milk.label)
        app.buttons["Clear Done"].tap()
        XCTAssertTrue(milk.waitForNonExistence(timeout: 5), "cleared")
        app.buttons["Undo"].tap()
        XCTAssertTrue(item("Milk").waitForExistence(timeout: 5), "back after undo")
    }

    func testAddingAnItemFromTheAddSheet() {
        app.navigationBars["Groceries"].buttons["Add"].tap()
        let sheet = app.navigationBars["New Item"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.textFields["Item name"].tap()
        app.textFields["Item name"].typeText("Yogurt")
        sheet.buttons["Add"].tap()
        XCTAssertTrue(item("Yogurt").waitForExistence(timeout: 5))
    }

    func testSwitchingStoresChangesTheTitle() {
        app.buttons["Kroger"].tap()
        XCTAssertTrue(app.navigationBars["Kroger"].waitForExistence(timeout: 5))
        app.buttons["All"].tap()
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 5))
    }

    private typealias Screen = (entry: String, submenu: String?, title: String)

    /// Opens each screen from the More menu, checks its title, and closes it again.
    private func openAndClose(_ screens: [Screen]) {
        for screen in screens {
            XCTContext.runActivity(named: screen.entry) { _ in
                app.buttons["More"].tap()
                if let submenu = screen.submenu {
                    let group = app.buttons[submenu].firstMatch
                    XCTAssertTrue(group.waitForExistence(timeout: 5), "\(submenu) submenu")
                    group.tap()
                }
                let entry = app.buttons[screen.entry].firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(screen.entry) in the menu")
                entry.tap()
                XCTAssertTrue(app.navigationBars[screen.title].waitForExistence(timeout: 10), "\(screen.title) opens")
                dismissSheet()
            }
        }
    }

    func testTopLevelMenuScreensOpenAndClose() {
        openAndClose([
            ("Usual & Buy Again", nil, "Usual & Buy Again"),
            ("Pantry Check", nil, "Pantry Check"),
            ("At Home", nil, "At Home"),
            ("Scan to Check Off", nil, "Scan to Check Off"),
            ("Send List to Family", nil, "Send to Family"),
        ])
    }

    func testMealsAndMoneyScreensOpenAndClose() {
        openAndClose([
            ("Saved Meals", "Meals", "Meals"),
            ("Meal Plan", "Meals", "Meal Plan"),
            ("Spending", "Money", "Spending"),
            ("Totals by Store", "Money", "Totals"),
            ("Plan the Trip", "Money", "Plan the Trip"),
            ("Scan Receipt", "Money", "Scan Receipt"),
        ])
    }

    func testSettingsScreensOpenAndClose() {
        openAndClose([
            ("Allergies & Avoid List", "Settings", "Allergies & Avoid List"),
            ("App Icon", "Settings", "App Icon"),
            ("Back Up & Restore", "Settings", "Back Up & Restore"),
        ])
    }

    func testImportingARecipeFromPastedText() {
        app.buttons["More"].tap()
        app.buttons["Meals"].firstMatch.tap()
        app.buttons["Saved Meals"].tap()
        let meals = app.navigationBars["Meals"]
        XCTAssertTrue(meals.waitForExistence(timeout: 10))
        meals.buttons["Add"].tap()
        app.buttons["Import Recipe…"].tap()
        XCTAssertTrue(app.navigationBars["Import Recipe"].waitForExistence(timeout: 10))

        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("2 cups rice\n3 eggs\n1 onion")
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Test Meal")
        app.navigationBars["Import Recipe"].buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Test Meal"].waitForExistence(timeout: 10), "the new meal opens")
        XCTAssertTrue(app.staticTexts["2 cups"].exists, "amounts are kept")
    }
}
