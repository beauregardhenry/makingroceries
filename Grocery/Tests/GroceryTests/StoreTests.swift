import XCTest

final class ItemTests: StoreTestCase {
    func testAddOrBumpMergesPlurals() {
        store.add(name: "Tomatoes", quantity: 1, aisle: .produce)
        store.addOrBump(name: "tomatos", shopID: nil)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.quantity, 2)
        XCTAssertEqual(store.canonicalName(for: "TOMATOES"), "Tomatoes")
        XCTAssertEqual(store.canonicalName(for: "tomato"), "Tomatoes")
    }

    func testTypoCatchingIsCautious() {
        store.add(name: "Cheddar", quantity: 1, aisle: .dairy)
        store.add(name: "Beets", quantity: 1, aisle: .produce)
        XCTAssertEqual(store.canonicalName(for: "Chedar"), "Cheddar")
        XCTAssertEqual(store.canonicalName(for: "Lime"), "Lime")
        XCTAssertEqual(store.canonicalName(for: "Rice"), "Rice")
        XCTAssertEqual(store.canonicalName(for: "Beans"), "Beans")
    }

    func testBumpOnlyMergesWithinTheSameStore() {
        let kroger = store.addShop(named: "Kroger")!
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: kroger.id)
        store.addOrBump(name: "Milk", shopID: nil)
        XCTAssertEqual(store.items.count, 2)
    }

    func testCheckingOffRecordsOnePurchasePerDay() {
        store.history = [PastItem(name: "Rice", aisle: .pantry, shopID: nil, price: nil)]
        store.items = [GroceryItem(name: "Rice", aisle: .pantry)]
        for _ in 0..<3 { store.toggle(store.items[0]) }
        XCTAssertEqual(store.history[0].purchases?.count, 1)
    }

    func testDueItemsFollowThePurchasePace() {
        let now = Date()
        let weekly: [TimeInterval] = [29, 22, 15, 8].map { now.timeIntervalSince1970 - $0 * 86_400 }
        store.history = [PastItem(name: "Eggs", aisle: .dairy, shopID: nil, price: nil)]
        store.history[0].purchases = weekly.map { Date(timeIntervalSince1970: $0) }
        XCTAssertEqual(store.dueItems(now: now).map(\.name), ["Eggs"])
        store.history[0].purchases?.append(now.addingTimeInterval(-86_400))
        XCTAssertTrue(store.dueItems(now: now).isEmpty)
        store.history[0].purchases = Array(store.history[0].purchases!.prefix(2))
        XCTAssertTrue(store.dueItems(now: now).isEmpty)
    }

    func testPriceHintPointsToTheCheaperStore() {
        let kroger = store.addShop(named: "Kroger")!, walmart = store.addShop(named: "Walmart")!
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: kroger.id, price: 4.29)
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: walmart.id, price: 3.49)
        let pricey = store.items.first { $0.shopID == kroger.id }!
        let cheap = store.items.first { $0.shopID == walmart.id }!
        XCTAssertEqual(store.priceHint(for: pricey), "Cheaper at Walmart: $3.49")
        XCTAssertNil(store.priceHint(for: cheap))
    }

    func testRepeatingItemsReturnOnSchedule() {
        let now = Date()
        store.recurring = [RecurringItem(name: "Bread", quantity: 1, aisle: .bakery, shopID: nil, everyDays: 7, nextDue: now - 2 * 86_400)]
        store.applyRecurring(now: now)
        XCTAssertEqual(store.items.map(\.name), ["Bread"])
        XCTAssertGreaterThan(store.recurring[0].nextDue, now)
        store.applyRecurring(now: now)
        XCTAssertEqual(store.items.count, 1)
    }

    func testUndoRestoresItemsInPlace() {
        store.items = (1...5).map { GroceryItem(name: "I\($0)") }
        store.toggle(store.items[1])
        store.toggle(store.items[3])
        let removed = store.clearChecked()
        XCTAssertEqual(store.items.map(\.name), ["I1", "I3", "I5"])
        store.restore(removed)
        XCTAssertEqual(store.items.map(\.name), ["I1", "I2", "I3", "I4", "I5"])
    }

    func testSizesAndHistoryCarryOver() {
        store.add(name: "Peanut butter", quantity: 1, aisle: .pantry, sizeAmount: 16, sizeUnit: "oz", barcode: "123")
        store.add(name: "Peanut butter", quantity: 1, aisle: .pantry)
        XCTAssertEqual(store.items.last?.sizeAmount, 16)
        XCTAssertEqual(store.pastItem(forBarcode: "123")?.name, "Peanut butter")
    }
}

final class ShopTests: StoreTestCase {
    func testShopsAreUniqueAndDeletingKeepsItems() {
        let kroger = store.addShop(named: "Kroger")!
        XCTAssertNil(store.addShop(named: "kroger"))
        XCTAssertNil(store.addShop(named: "  "))
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: kroger.id)
        store.deleteShop(kroger)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items[0].shopID)
    }

    func testAisleOrderCoversEveryAisleOnce() {
        var shop = Shop(name: "Kroger")
        shop.aisleOrder = [.bakery, .bakery, .produce]
        XCTAssertEqual(Set(shop.orderedAisles), Set(Aisle.allCases))
        XCTAssertEqual(shop.orderedAisles.count, Aisle.allCases.count)
        XCTAssertEqual(Array(shop.orderedAisles.prefix(2)), [.bakery, .produce])
    }

    private func priorTrips(for shop: Shop) -> [RouteEvent] {
        (1...3).flatMap { back -> [RouteEvent] in
            let start = Date().addingTimeInterval(Double(-back) * 86_400)
            return [Aisle.bakery, .produce, .dairy].enumerated().map { RouteEvent(aisle: $1, date: start + Double($0) * 300) }
        }
    }

    func testRouteIsLearnedFromCheckOffs() {
        let kroger = store.addShop(named: "Kroger")!
        store.shops[0].routeEvents = priorTrips(for: kroger)
        store.items = [GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id)]
        store.toggle(store.items[0])
        // Aisles that were never shopped keep their slots, so only the shopped ones are reordered.
        let order = store.shops[0].orderedAisles
        XCTAssertLessThan(order.firstIndex(of: .bakery)!, order.firstIndex(of: .produce)!)
        XCTAssertLessThan(order.firstIndex(of: .produce)!, order.firstIndex(of: .dairy)!)
        XCTAssertEqual(order.firstIndex(of: .meat), 2)
        XCTAssertGreaterThanOrEqual(store.tripCount(for: store.shops[0]), 3)
    }

    func testTurningLearningOffLeavesTheOrderAlone() {
        let kroger = store.addShop(named: "Kroger")!
        store.shops[0].learnRoute = false
        store.shops[0].routeEvents = priorTrips(for: kroger)
        store.items = [GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id)]
        store.toggle(store.items[0])
        XCTAssertEqual(store.shops[0].orderedAisles, Aisle.allCases)
    }

    func testOldSavedShopsStillDecode() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Kroger"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(Shop.self, from: old).name, "Kroger")
        let oldItem = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Milk","quantity":1,"aisle":"Dairy & Eggs","isChecked":false}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(GroceryItem.self, from: oldItem).name, "Milk")
        let oldBackup = #"{"version":1,"items":[],"shops":[],"favorites":[],"meals":[],"history":[],"recurring":[]}"#.data(using: .utf8)!
        XCTAssertNoThrow(try JSONDecoder().decode(Backup.self, from: oldBackup))
    }

    func testBackupRoundTrip() throws {
        store.add(name: "Milk", quantity: 2, aisle: .dairy)
        store.recordSpend(amount: 10, shopID: nil)
        let data = try JSONEncoder().encode(store.makeBackup())
        let decoded = try JSONDecoder().decode(Backup.self, from: data)
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.spending?.count, 1)
    }
}

final class TripPlannerTests: StoreTestCase {
    private var kroger: Shop!, walmart: Shop!, chinese: Shop!

    override func setUp() {
        super.setUp()
        kroger = store.addShop(named: "Kroger")
        walmart = store.addShop(named: "Walmart")
        chinese = store.addShop(named: "Chinese Grocery")
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: kroger.id, price: 4.29)
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: walmart.id, price: 3.49)
        store.add(name: "Rice", quantity: 2, aisle: .pantry, shopID: chinese.id, price: 14.99)
        store.add(name: "Rice", quantity: 1, aisle: .pantry, shopID: walmart.id, price: 9.99)
        store.add(name: "Eggs", quantity: 1, aisle: .dairy, shopID: kroger.id, price: 2.00)
        store.items = [
            GroceryItem(name: "Milk", quantity: 1, aisle: .dairy, shopID: kroger.id, price: 4.29),
            GroceryItem(name: "Rice", quantity: 2, aisle: .pantry, shopID: chinese.id, price: 14.99),
            GroceryItem(name: "Eggs", quantity: 1, aisle: .dairy, shopID: kroger.id, price: 2.00),
            GroceryItem(name: "Paper towels", quantity: 1, aisle: .household, shopID: walmart.id, price: 8.97),
        ]
    }

    func testSuggestsOnlyRealSavingsAtStopsAlreadyOnTheTrip() {
        let plan = store.tripPlan()
        XCTAssertEqual(plan.map(\.item.name), ["Rice", "Milk"])
        XCTAssertEqual(plan[0].savings, 10.0, accuracy: 0.001)
        XCTAssertEqual(plan[1].savings, 0.80, accuracy: 0.001)
    }

    func testNoSuggestionsForStoresThatAreNotOnTheTrip() {
        store.items.removeAll { $0.name == "Paper towels" }
        XCTAssertTrue(store.tripPlan().isEmpty)
        store.items.append(GroceryItem(name: "Paper towels", quantity: 1, aisle: .household, isChecked: true, shopID: walmart.id, price: 8.97))
        XCTAssertTrue(store.tripPlan().isEmpty)
    }

    func testApplyingMovesItemsAndUpdatesPrices() {
        store.applyTripMoves(store.tripPlan())
        XCTAssertEqual(store.items.first { $0.name == "Rice" }?.shopID, walmart.id)
        XCTAssertEqual(store.items.first { $0.name == "Rice" }?.price, 9.99)
        XCTAssertTrue(store.tripPlan().isEmpty)
    }

    func testUnassignedItemsGoToTheCheapestStop() {
        store.items = [GroceryItem(name: "Milk", quantity: 1, aisle: .dairy), GroceryItem(name: "Eggs", shopID: kroger.id), GroceryItem(name: "Bleach", shopID: walmart.id)]
        let moves = store.tripPlan()
        XCTAssertEqual(moves.first?.to, walmart.id)
        XCTAssertEqual(moves.first?.savings ?? 0, 0.80, accuracy: 0.001)
    }

    func testReceiptPricesLandOnItemsAndHistory() {
        store.items = [GroceryItem(name: "Chicken thighs", quantity: 1, aisle: .meat, shopID: kroger.id)]
        let entry = ReceiptEntry(name: "Bnls Chkn Thigh", quantity: 1, unitPrice: 7.99, total: 7.99)
        XCTAssertEqual(store.applyReceipt([(entry: entry, item: store.items[0])], shopID: kroger.id), 1)
        XCTAssertEqual(store.items[0].price, 7.99)
        XCTAssertEqual(store.latestPrices(for: "Chicken thighs")[kroger.id], 7.99)
    }
}

final class MealPlanTests: StoreTestCase {
    private var curry: Meal!, pasta: Meal!

    override func setUp() {
        super.setUp()
        curry = Meal(name: "Curry", ingredients: [MealIngredient(name: "Rice", quantity: 1, amount: 2, unit: "cup"), MealIngredient(name: "Onion", quantity: 2)])
        pasta = Meal(name: "Pasta", ingredients: [MealIngredient(name: "Spaghetti", quantity: 1), MealIngredient(name: "Onion", quantity: 1)])
        store.meals = [curry, pasta]
        store.addPlan(curry, on: day(1))
        store.addPlan(pasta, on: day(3))
        store.addPlan(curry, on: day(9))
    }

    func testPlanningAndAddingTheWeek() {
        XCTAssertEqual(store.planned(on: day(1)).count, 1)
        XCTAssertEqual(store.upcomingPlan().count, 3)
        XCTAssertEqual(store.addPlannedToList(days: 5, shopID: nil), 2)
        XCTAssertEqual(store.items.first { $0.name == "Onion" }?.quantity, 3)
        XCTAssertEqual(store.items.first { $0.name == "Rice" }?.note, "2 cups")
        XCTAssertEqual(store.addPlannedToList(days: 5, shopID: nil), 0)
        XCTAssertEqual(store.addPlannedToList(days: 14, shopID: nil), 1)
    }

    func testPastPlansAndDeletedMealsAreIgnored() {
        store.plan.append(PlannedMeal(mealID: curry.id, day: day(-2)))
        XCTAssertTrue(store.upcomingPlan().allSatisfy { $0.day >= day(0) })
        store.meals.removeAll { $0.id == pasta.id }
        XCTAssertTrue(store.upcomingPlan().allSatisfy { $0.mealID != pasta.id })
    }

    func testScalingAMealWhenAddingIt() {
        store.items = []
        store.addToList(curry, shopID: nil, scale: 2)
        XCTAssertEqual(store.items.first { $0.name == "Rice" }?.note, "4 cups")
        XCTAssertEqual(store.items.first { $0.name == "Onion" }?.quantity, 4)
    }

    func testMakeMealFromPastedLines() {
        let meal = store.makeMeal(named: "", fromLines: "2 cups rice\n3 eggs")
        XCTAssertEqual(meal.name, "Imported recipe")
        XCTAssertEqual(meal.ingredients.map(\.name), ["Rice", "Eggs"])
        XCTAssertEqual(meal.ingredients[0].unit, "cup")
    }
}

final class StockAndSpendingTests: StoreTestCase {
    func testPerishablesGoAtHomeWithAUseByDate() {
        store.items = [GroceryItem(name: "Spinach", aisle: .produce), GroceryItem(name: "Dish soap", aisle: .household)]
        store.toggle(store.items[0])
        store.toggle(store.items[1])
        XCTAssertEqual(store.stock.map(\.name), ["Spinach"])
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: store.stock[0].expires)).day
        XCTAssertEqual(days, 5)
        XCTAssertTrue(store.usingSoon(within: 3).isEmpty)
        XCTAssertEqual(store.usingSoon(within: 5).count, 1)
    }

    func testRebuyingReplacesAndTrackingCanBeTurnedOff() {
        store.items = [GroceryItem(name: "Spinach", aisle: .produce)]
        store.toggle(store.items[0]); store.toggle(store.items[0]); store.toggle(store.items[0])
        XCTAssertEqual(store.stock.count, 1)
        GroceryStore.tracksStock = false
        store.items = [GroceryItem(name: "Milk", aisle: .dairy)]
        store.toggle(store.items[0])
        XCTAssertEqual(store.stock.count, 1)
    }

    func testUsingUpCanPutItBackOnTheList() {
        store.items = [GroceryItem(name: "Spinach", aisle: .produce)]
        store.toggle(store.items[0])
        store.useUp(store.stock[0], addBack: true)
        XCTAssertTrue(store.stock.isEmpty)
        XCTAssertTrue(store.items.contains { $0.name == "Spinach" && !$0.isChecked })
    }

    func testSpendingTotalsAndBreakdowns() {
        let kroger = store.addShop(named: "Kroger")!, walmart = store.addShop(named: "Walmart")!
        let now = Date()
        store.recordSpend(amount: 50, on: day(-1, from: now), shopID: kroger.id, byAisle: ["Produce": 20, "Dairy & Eggs": 30])
        store.recordSpend(amount: 30, on: day(-2, from: now), shopID: walmart.id)
        store.recordSpend(amount: 40, on: day(-9, from: now), shopID: kroger.id, byAisle: ["Produce": 10, "Pantry": 30])
        store.recordSpend(amount: 0, shopID: nil)
        XCTAssertEqual(store.spending.count, 3)
        XCTAssertEqual(store.weeklyTotals(weeks: 4, now: now).reduce(0) { $0 + $1.amount }, 120, accuracy: 0.001)
        let byShop = store.spendingByShop(from: day(-30, from: now), to: now.addingTimeInterval(60))
        XCTAssertEqual(byShop.first?.label, "Kroger")
        XCTAssertEqual(byShop.first?.amount, 90)
        let byAisle = store.spendingByAisle(from: day(-30, from: now), to: now.addingTimeInterval(60))
        XCTAssertEqual(byAisle.map(\.label), ["Dairy & Eggs", "Pantry", "Produce"])
        XCTAssertEqual(byAisle.first { $0.label == "Produce" }?.amount, 30)
        XCTAssertEqual(store.spent(from: day(-3, from: now), to: now.addingTimeInterval(60)), 80)
    }

    func testBudgetIsSavedAndCleared() {
        GroceryStore.monthlyBudget = 200
        XCTAssertEqual(GroceryStore.monthlyBudget, 200)
        GroceryStore.monthlyBudget = nil
        XCTAssertNil(GroceryStore.monthlyBudget)
    }
}

final class ListExchangeTests: StoreTestCase {
    private func makeExport() -> (ListExport, Shop) {
        let kroger = store.addShop(named: "Kroger")!
        store.items = [GroceryItem(name: "Milk", quantity: 2, aisle: .dairy, shopID: kroger.id, price: 3.49),
                       GroceryItem(name: "Bread", aisle: .bakery, shopID: kroger.id),
                       GroceryItem(name: "Rice", aisle: .pantry)]
        return (store.makeExport(), kroger)
    }

    func testFileRoundTrip() throws {
        let (export, _) = makeExport()
        let url = try XCTUnwrap(store.exportFile(export))
        XCTAssertEqual(url.pathExtension, "makinglist")
        let back = try XCTUnwrap(GroceryStore.readExport(from: url))
        XCTAssertEqual(back.items.count, 3)
        XCTAssertEqual(back.items[0].shopName, "Kroger")
        XCTAssertNil(GroceryStore.readExport(from: URL(fileURLWithPath: "/nonexistent")))
        let bad = FileManager.default.temporaryDirectory.appending(path: "bad.makinglist")
        try "not json".write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertNil(GroceryStore.readExport(from: bad))
    }

    func testMergeAddsNewItemsAndMarksBoughtButNeverUnbuys() {
        let (export, kroger) = makeExport()
        var theirs = export
        theirs.items[1].isChecked = true
        theirs.items.append(.init(id: UUID(), name: "Eggs", quantity: 1, aisle: .dairy, isChecked: false, shopName: "Aldi", price: nil, note: nil))

        store.items = [GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id)]   // same name and store, different id
        let preview = store.mergeImport(theirs, apply: false)
        XCTAssertEqual(preview.added, 3)
        XCTAssertEqual(preview.unchanged, 1)
        XCTAssertEqual(store.shops.count, 1)

        let done = store.mergeImport(theirs)
        XCTAssertEqual(done.newStores, ["Aldi"])
        XCTAssertEqual(store.items.count, 4)
        XCTAssertTrue(store.items.first { $0.name == "Bread" }!.isChecked)

        XCTAssertEqual(store.mergeImport(theirs).added, 0)
        var undone = theirs
        undone.items[1].isChecked = false
        store.mergeImport(undone)
        XCTAssertTrue(store.items.first { $0.name == "Bread" }!.isChecked)
    }

    func testExportCanBeLimitedToOneStoreAndUnchecked() {
        let (_, kroger) = makeExport()
        store.toggle(store.items[0])
        XCTAssertEqual(store.makeExport(shopID: kroger.id).items.count, 2)
        XCTAssertEqual(store.makeExport(onlyUnchecked: true).items.count, 2)
    }
}

final class BarcodeCheckOffTests: StoreTestCase {
    private var kroger: Shop!

    override func setUp() {
        super.setUp()
        kroger = store.addShop(named: "Kroger")
        store.items = [GroceryItem(name: "Hazelnut spread", aisle: .pantry, shopID: kroger.id),
                       GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id)]
        store.history = [PastItem(name: "Hazelnut spread", aisle: .pantry, shopID: kroger.id, price: nil),
                         PastItem(name: "Milk", aisle: .dairy, shopID: kroger.id, price: nil)]
    }

    @MainActor
    func testFirstScanMatchesByNameThenRemembersTheBarcode() async {
        var outcome = await store.checkOff(barcode: "111", preferring: kroger.id) { _ in nil }
        XCTAssertEqual(outcome, .unknown)

        outcome = await store.checkOff(barcode: "3017620422003", preferring: kroger.id) { _ in "Nutella hazelnut spread" }
        XCTAssertEqual(outcome, .ticked("Hazelnut spread"))
        XCTAssertEqual(store.pastItem(forBarcode: "3017620422003")?.name, "Hazelnut spread")

        outcome = await store.checkOff(barcode: "3017620422003", preferring: kroger.id) { _ in nil }
        XCTAssertEqual(outcome, .alreadyBought("Hazelnut spread"))

        store.items[0].isChecked = false
        outcome = await store.checkOff(barcode: "3017620422003", preferring: kroger.id) { _ in
            XCTFail("a known barcode needs no lookup")
            return nil
        }
        XCTAssertEqual(outcome, .ticked("Hazelnut spread"))
    }

    @MainActor
    func testProductsNotOnTheListAndLookalikes() async {
        var outcome = await store.checkOff(barcode: "222", preferring: kroger.id) { _ in "Quinoa" }
        XCTAssertEqual(outcome, .notOnList("Quinoa"))
        outcome = await store.checkOff(barcode: "333", preferring: kroger.id) { _ in "Whole Milk 1 gal" }
        XCTAssertEqual(outcome, .ticked("Milk"))
    }
}

final class WatchSnapshotTests: StoreTestCase {
    func testGroupsFollowStoresAndWalkingOrder() throws {
        let kroger = store.addShop(named: "Kroger")!, walmart = store.addShop(named: "Walmart")!
        store.shops[0].aisleOrder = [.bakery, .produce, .dairy, .meat, .pantry, .frozen, .drinks, .household, .other]
        store.items = [
            GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id),
            GroceryItem(name: "Bananas", quantity: 6, aisle: .produce, shopID: kroger.id, note: "ripe"),
            GroceryItem(name: "Bread", aisle: .bakery, isChecked: true, shopID: kroger.id),
            GroceryItem(name: "Soap", aisle: .household, shopID: walmart.id),
            GroceryItem(name: "Salt", aisle: .pantry),
        ]
        let snapshot = store.watchSnapshot()
        XCTAssertEqual(snapshot.groups.map(\.name), ["Kroger", "Walmart", "Any Store"])
        XCTAssertEqual(snapshot.groups[0].items.map(\.name), ["Bread", "Bananas", "Milk"])
        XCTAssertEqual(snapshot.groups[0].remaining, 2)
        XCTAssertEqual(snapshot.groups[0].items[1].quantity, 6)
        XCTAssertEqual(snapshot.groups[0].items[1].note, "ripe")
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WatchSnapshot.self, from: data), snapshot)
    }

    func testEmptyStoresAreLeftOutAndLongListsAreCapped() {
        let kroger = store.addShop(named: "Kroger")!
        _ = store.addShop(named: "Walmart")
        store.items = (0..<100).map { GroceryItem(name: "Item \($0)", aisle: .pantry, shopID: kroger.id) }
        let snapshot = store.watchSnapshot()
        XCTAssertEqual(snapshot.groups.map(\.name), ["Kroger"])
        XCTAssertEqual(snapshot.groups[0].items.count, WatchSnapshot.maxItemsPerGroup)
    }
}

final class ItemEditingTests: StoreTestCase {
    func testMovingAndPricingAnItem() {
        let kroger = store.addShop(named: "Kroger")!
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        store.move(store.items[0], to: kroger.id)
        XCTAssertEqual(store.items[0].shopID, kroger.id)
        store.setPrice(3.49, for: store.items[0])
        XCTAssertEqual(store.items[0].price, 3.49)
        // A price change is remembered but isn't another use of the item.
        XCTAssertEqual(store.pastItem(named: "Milk")?.price, 3.49)
        XCTAssertEqual(store.pastItem(named: "Milk")?.count, 1)
    }

    func testDetailEditsSaveTheSizeAndDropTheOldPhoto() throws {
        let photo = "old-\(UUID().uuidString).jpg"
        let file = Storage.photos.appending(path: photo)
        try Data([1, 2, 3]).write(to: file)
        store.add(name: "Peanut butter", quantity: 1, aisle: .pantry)
        store.items[0].photo = photo
        var edited = store.items[0]
        edited.photo = nil
        edited.sizeAmount = 16
        edited.sizeUnit = "oz"
        store.update(edited)
        XCTAssertNil(store.items[0].photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.pastItem(named: "Peanut butter")?.sizeAmount, 16)
        XCTAssertEqual(store.pastItem(named: "Peanut butter")?.sizeUnit, "oz")
    }

    func testAPhotoAnotherItemStillUsesIsKept() throws {
        let photo = "shared-\(UUID().uuidString).jpg"
        let file = Storage.photos.appending(path: photo)
        try Data([1]).write(to: file)
        store.items = [GroceryItem(name: "Apples", photo: photo), GroceryItem(name: "Pears", photo: photo)]
        store.delete(store.items[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.delete(store.items[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAddingAgainUsesTheStoreItWasBoughtAtLastTime() {
        let kroger = store.addShop(named: "Kroger")!
        store.history = [PastItem(name: "Coffee", aisle: .drinks, shopID: kroger.id, price: 8.99)]
        store.addOrBump(name: "Coffee", shopID: nil, inferShop: true)
        XCTAssertEqual(store.items[0].shopID, kroger.id)
        XCTAssertEqual(store.items[0].price, 8.99)
        // Without inferShop, or once that store is gone, it stays unassigned.
        store.items = []
        store.addOrBump(name: "Coffee", shopID: nil)
        XCTAssertNil(store.items[0].shopID)
        store.items = []
        store.deleteShop(kroger)
        store.addOrBump(name: "Coffee", shopID: nil, inferShop: true)
        XCTAssertNil(store.items[0].shopID)
    }

    func testReceiptLinesWithNoListItemStillRecordAPrice() {
        let kroger = store.addShop(named: "Kroger")!
        let entry = ReceiptEntry(name: "Bananas", unitPrice: 0.59, total: 0.59)
        XCTAssertEqual(store.applyReceipt([(entry: entry, item: nil)], shopID: kroger.id), 1)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.latestPrices(for: "Bananas")[kroger.id], 0.59)
    }

    func testWidgetItemsFollowTheStoreWalkingOrder() {
        let kroger = store.addShop(named: "Kroger")!
        store.shops[0].aisleOrder = [.bakery, .dairy, .produce]
        store.items = [
            GroceryItem(name: "Spinach", aisle: .produce, shopID: kroger.id),
            GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id),
            GroceryItem(name: "Bread", aisle: .bakery, shopID: kroger.id),
            GroceryItem(name: "Eggs", aisle: .dairy, isChecked: true, shopID: kroger.id),
            GroceryItem(name: "Soap", aisle: .household),
        ]
        XCTAssertEqual(store.widgetItems(shopID: kroger.id).map(\.name), ["Bread", "Milk", "Spinach"])
        XCTAssertEqual(store.widgetItems(shopID: nil).count, 4)
    }
}

final class UsualAndRepeatTests: StoreTestCase {
    func testUsualItemsAreUniqueAndGoOnTheList() {
        store.history = [PastItem(name: "Oat milk", aisle: .dairy, shopID: nil, price: nil)]
        store.addFavorite(name: "  Oat milk ", quantity: 2)
        store.addFavorite(name: "oat milk")
        store.addFavorite(name: " ")
        XCTAssertEqual(store.favorites.map(\.name), ["Oat milk"])
        XCTAssertEqual(store.favorites[0].aisle, .dairy)
        store.addToList(store.favorites[0], shopID: nil)
        store.addToList(store.favorites[0], shopID: nil)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].quantity, 4)
    }

    func testTurningARepeatOnAndOff() {
        let item = GroceryItem(name: "Bread", aisle: .bakery)
        store.setRepeat(for: item, everyDays: 7)
        store.setRepeat(for: item, everyDays: 14)
        XCTAssertEqual(store.recurring.count, 1)
        XCTAssertEqual(store.recurrence(for: item)?.everyDays, 14)
        XCTAssertGreaterThan(store.recurring[0].nextDue, day(13))
        store.setRepeat(for: item, everyDays: nil)
        XCTAssertNil(store.recurrence(for: item))
    }

    func testRestoringABackupReplacesEverything() throws {
        store.add(name: "Milk", quantity: 2, aisle: .dairy)
        _ = store.addShop(named: "Kroger")
        store.addFavorite(name: "Coffee")
        store.recordSpend(amount: 10, shopID: nil)
        let data = try JSONEncoder().encode(store.makeBackup())

        store.items = [GroceryItem(name: "Something else")]
        store.shops = []
        store.favorites = []
        store.spending = []
        store.restore(try JSONDecoder().decode(Backup.self, from: data))
        XCTAssertEqual(store.items.map(\.name), ["Milk"])
        XCTAssertEqual(store.shops.map(\.name), ["Kroger"])
        XCTAssertEqual(store.favorites.map(\.name), ["Coffee"])
        XCTAssertEqual(store.spending.count, 1)
    }

    func testRestoringAnOldBackupClearsNewerData() throws {
        store.recordSpend(amount: 10, shopID: nil)
        let old = #"{"version":1,"items":[],"shops":[],"favorites":[],"meals":[],"history":[],"recurring":[]}"#.data(using: .utf8)!
        store.restore(try JSONDecoder().decode(Backup.self, from: old))
        XCTAssertTrue(store.spending.isEmpty)
        XCTAssertTrue(store.plan.isEmpty)
        XCTAssertTrue(store.stock.isEmpty)
    }
}

final class SuggestionTests: StoreTestCase {
    private func past(_ name: String, count: Int, daysAgo: Int) -> PastItem {
        var item = PastItem(name: name, aisle: .other, shopID: nil, price: nil)
        item.count = count
        item.lastUsed = day(-daysAgo)
        return item
    }

    func testAutocompleteRanksByUseAndSkipsWhatsOnTheList() {
        store.history = [past("Cheddar", count: 2, daysAgo: 1), past("Cherries", count: 5, daysAgo: 9),
                         past("Chips", count: 2, daysAgo: 3), past("Che", count: 9, daysAgo: 0), past("Milk", count: 9, daysAgo: 0)]
        store.items = [GroceryItem(name: "Chips")]
        XCTAssertEqual(store.suggestions(for: " CHE").map(\.name), ["Cherries", "Cheddar"])
        XCTAssertEqual(store.suggestions(for: "ch", limit: 1).map(\.name), ["Che"])
        XCTAssertTrue(store.suggestions(for: "  ").isEmpty)
    }

    func testBuyAgainIsNewestFirstAndSkipsWhatsOnTheList() {
        store.history = [past("Rice", count: 1, daysAgo: 5), past("Eggs", count: 1, daysAgo: 1), past("Milk", count: 1, daysAgo: 2)]
        store.items = [GroceryItem(name: "Milk")]
        XCTAssertEqual(store.buyAgain().map(\.name), ["Eggs", "Rice"])
        XCTAssertEqual(store.buyAgain(limit: 1).map(\.name), ["Eggs"])
        // Checked-off items count as bought, so they come back here.
        store.items[0].isChecked = true
        XCTAssertEqual(store.buyAgain().map(\.name), ["Eggs", "Milk", "Rice"])
    }
}

final class ModelTests: XCTestCase {
    func testEveryAisleHasItsOwnSymbol() {
        let symbols = Aisle.allCases.map(\.symbol)
        XCTAssertFalse(symbols.contains(""))
        XCTAssertEqual(Set(symbols).count, Aisle.allCases.count)
    }

    func testScalingIngredients() {
        let flour = MealIngredient(name: "Flour", aisle: .pantry, amount: 2, unit: "cup")
        XCTAssertEqual(flour.scaled(by: 1).quantity, 1)
        XCTAssertNotEqual(flour.scaled(by: 1).note, flour.scaled(by: 1.5).note)
        let eggs = MealIngredient(name: "Eggs", quantity: 3, aisle: .dairy)
        XCTAssertEqual(eggs.scaled(by: 0.5).quantity, 2)
        XCTAssertEqual(eggs.scaled(by: 0.1).quantity, 1)
        XCTAssertEqual(eggs.scaled(by: 2).quantity, 6)
        XCTAssertNil(eggs.scaled(by: 2).note)
    }

    func testAisleLabelsIgnoreBlanks() {
        var shop = Shop(name: "Kroger")
        shop.aisleLabels = [Aisle.dairy.rawValue: " Aisle 7 ", Aisle.produce.rawValue: "  "]
        XCTAssertEqual(shop.label(for: .dairy), "Aisle 7")
        XCTAssertNil(shop.label(for: .produce))
        XCTAssertNil(shop.label(for: .meat))
    }
}
