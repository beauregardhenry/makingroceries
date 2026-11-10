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

    private func dismissSheet(backTo title: String = "Groceries", file: StaticString = #filePath, line: UInt = #line) {
        // A sheet over a sheet leaves the lower one's Done in the tree too, so take the one on screen.
        for name in ["Done", "Close", "Cancel"] {
            let matches = app.navigationBars.buttons.matching(identifier: name).allElementsBoundByIndex
            if let button = matches.last(where: { $0.exists && $0.isHittable }) {
                button.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "back on \(title)", file: file, line: line)
                return
            }
        }
        XCTFail("no Done, Close or Cancel button to close the sheet", file: file, line: line)
    }

    func testLaunchShowsTheSampleListAndStores() {
        XCTAssertTrue(item("Bananas").exists)
        XCTAssertTrue(item("Milk").exists)
        XCTAssertTrue(item("Sourdough").exists)
        for store in ["All", "Kroger", "Walmart", "Online"] {
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

    /// Taps a More menu entry, inside `submenu` if given. On a slow simulator a tap on More sometimes
    /// lands before the screen is ready and the menu never opens, so it taps More once more if needed.
    private func chooseFromMore(_ entry: String, in submenu: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let first = app.buttons[submenu ?? entry].firstMatch
        app.buttons["More"].tap()
        if !first.waitForExistence(timeout: 5) {
            app.buttons["More"].tap()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 5), "\(submenu ?? entry) in the More menu", file: file, line: line)
        first.tap()
        if let submenu {
            let item = app.buttons[entry].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(entry) in the \(submenu) submenu", file: file, line: line)
            item.tap()
        }
    }

    /// Opens each screen from the More menu, checks its title, and closes it again.
    private func openAndClose(_ screens: [Screen]) {
        for screen in screens {
            XCTContext.runActivity(named: screen.entry) { _ in
                chooseFromMore(screen.entry, in: screen.submenu)
                XCTAssertTrue(app.navigationBars[screen.title].waitForExistence(timeout: 10), "\(screen.title) opens")
                dismissSheet()
            }
        }
    }

    /// Switches to a tab and waits for its screen.
    private func showTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab", file: file, line: line)
        tab.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), "\(name) opens", file: file, line: line)
    }

    /// Opens each screen from a tab's rows, checks its title, and closes it again.
    private func openAndClose(tab: String, _ screens: [(row: String, title: String)]) {
        showTab(tab)
        for screen in screens {
            XCTContext.runActivity(named: screen.row) { _ in
                let row = app.buttons[screen.row].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 5), "\(screen.row) on \(tab)")
                row.tap()
                XCTAssertTrue(app.navigationBars[screen.title].waitForExistence(timeout: 10), "\(screen.title) opens")
                dismissSheet(backTo: tab)
            }
        }
    }

    func testListMenuScreensOpenAndClose() {
        openAndClose([
            ("Scan to Check Off", nil, "Scan to Check Off"),
            ("Send List to Family", nil, "Send to Family"),
        ])
    }

    func testMealsTabScreensOpenAndClose() {
        openAndClose(tab: "Meals", [
            ("What Can I Cook?", "What Can I Cook?"),
            ("Saved Meals", "Saved Meals"),
            ("Meal Plan", "Meal Plan"),
            ("Company Coming", "Company Coming"),
        ])
    }

    func testSavingUpForAGoal() {
        showTab("Save Up")
        app.navigationBars.buttons["Add Goal"].tap()
        let name = app.textFields["What are you saving for?"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("New computer")
        let cost = app.textFields["$0.00"].firstMatch
        cost.tap()
        cost.typeText("1200")
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["goal-New computer"].waitForExistence(timeout: 5), "the goal is listed")
        XCTAssertTrue(app.buttons["Unexpected expense"].exists, "surprise expenses are one tap away")
    }

    func testCompanyComingOffersMakeAheadMeals() {
        showTab("Meals")
        app.buttons["Company Coming"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Company Coming"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Baked Ziti"].waitForExistence(timeout: 5), "built-in make-ahead ideas are listed")
        XCTAssertTrue(app.staticTexts["Make ahead, freezes well"].exists)
    }

    /// Chips in the horizontal store bar can sit past the screen edge, where isHittable can't answer.
    private func onScreen(_ element: XCUIElement) -> Bool {
        let width = app.windows.firstMatch.frame.width
        return element.exists && element.frame.minX >= 0 && element.frame.maxX <= width
    }

    func testTripItemsStayOffTheEverydayList() {
        // Travel sits after the stores, so the chip bar may need a swipe to reach it.
        let travel = app.buttons["Travel"]
        for _ in 0..<3 where !onScreen(travel) { app.buttons["All"].swipeLeft() }
        travel.tap()
        XCTAssertTrue(app.navigationBars["Travel"].waitForExistence(timeout: 5), "Travel is its own list")
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("passport holder")
        app.buttons["Add items"].tap()
        XCTAssertTrue(item("Passport holder").waitForExistence(timeout: 5), "it shows under Travel")
        for _ in 0..<3 where !onScreen(app.buttons["All"]) { travel.swipeRight() }
        app.buttons["All"].tap()
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(item("Milk").waitForExistence(timeout: 5))
        XCTAssertFalse(item("Passport holder").exists, "trip items don't clog the everyday list")
    }

    func testKitchenTabScreensOpenAndClose() {
        openAndClose(tab: "Kitchen", [
            ("At Home", "At Home"),
            ("Pantry Check", "Pantry Check"),
            ("Usual & Buy Again", "Usual & Buy Again"),
        ])
    }

    func testMoneyTabScreensOpenAndClose() {
        openAndClose(tab: "Money", [
            ("Spending", "Spending"),
            ("Price History", "Price History"),
            ("Totals by Store", "Totals"),
            ("Plan the Trip", "Plan the Trip"),
            ("Scan Receipt", "Scan Receipt"),
        ])
    }

    func testSettingsScreensOpenAndClose() {
        chooseFromMore("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings opens")
        for (row, title) in [("App Icon", "App Icon"), ("Stores", "Stores"), ("Allergies & Avoid List", "Allergies & Avoid List"),
                             ("iCloud Sync", "iCloud Sync"), ("Live Sync", "Live Sync"), ("Back Up & Restore", "Back Up & Restore")] {
            XCTContext.runActivity(named: row) { _ in
                app.buttons[row].firstMatch.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "\(title) opens")
                dismissSheet(backTo: "Settings")
            }
        }
        dismissSheet()
    }

    func testImportingARecipeFromPastedText() {
        showTab("Meals")
        app.buttons["Saved Meals"].firstMatch.tap()
        let meals = app.navigationBars["Saved Meals"]
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

    func testShoppingModeShowsProgressAndFinishes() {
        chooseFromMore("Shopping Mode")
        let done = app.navigationBars["Groceries"].buttons["Done Shopping"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Shopping Mode is on")
        XCTAssertTrue(app.staticTexts["0 of 3 in the cart"].waitForExistence(timeout: 5), "progress shows")
        item("Milk").tap()
        XCTAssertTrue(app.staticTexts["1 of 3 in the cart"].waitForExistence(timeout: 5), "progress moves")
        XCTAssertTrue(app.buttons["In the cart (1)"].waitForExistence(timeout: 5), "the cart is collapsed with a count")
        XCTAssertFalse(item("Milk").exists, "checked items are tucked away")
        done.tap()
        XCTAssertTrue(app.navigationBars["Groceries"].buttons["Clear Done"].waitForExistence(timeout: 5), "back to the normal list")
        XCTAssertFalse(item("Milk").exists, "what was in the cart is cleared")
        XCTAssertTrue(app.buttons["Undo"].exists, "and can be undone")
    }
}
