import XCTest

final class CookIdeasTests: StoreTestCase {
    private func stock(_ name: String, aisle: Aisle = .produce, daysLeft: Int) -> StockEntry {
        StockEntry(name: name, aisle: aisle, bought: day(-1), expires: day(daysLeft))
    }

    func testIngredientNamesMatchLoosely() {
        XCTAssertTrue(IngredientMatch.covers("Spinach", "baby spinach"))
        XCTAssertTrue(IngredientMatch.covers("Baby Spinach", "spinach"))
        XCTAssertTrue(IngredientMatch.covers("Tomatoes", "tomato"))
        XCTAssertTrue(IngredientMatch.covers("Berries", "berry"))
        XCTAssertFalse(IngredientMatch.covers("Cream", "cream cheese"))
        XCTAssertFalse(IngredientMatch.covers("Milk", "eggs"))
        XCTAssertFalse(IngredientMatch.covers("", "eggs"))
        XCTAssertEqual(IngredientMatch.singular("peaches"), "peach")
        XCTAssertEqual(IngredientMatch.singular("glass"), "glass")
    }

    func testMealsThatUseUpWhatsGoingOffComeFirst() {
        store.meals = [
            Meal(name: "Omelet", ingredients: [MealIngredient(name: "Eggs"), MealIngredient(name: "Cheddar")]),
            Meal(name: "Salad", ingredients: [MealIngredient(name: "Spinach"), MealIngredient(name: "Feta"), MealIngredient(name: "Walnuts")]),
            Meal(name: "Pasta", ingredients: [MealIngredient(name: "Penne")]),
        ]
        store.stock = [stock("Eggs", aisle: .dairy, daysLeft: 20), stock("Cheddar", aisle: .dairy, daysLeft: 25),
                       stock("Baby spinach", daysLeft: 1)]
        let matches = store.mealsFromHome()
        XCTAssertEqual(matches.map(\.meal.name), ["Salad", "Omelet"])
        XCTAssertEqual(matches[0].usesSoon, ["Baby spinach"])
        XCTAssertEqual(matches[0].missing.map(\.name), ["Feta", "Walnuts"])
        XCTAssertTrue(matches[1].missing.isEmpty)
    }

    func testFewerMissingWinsWhenNothingIsGoingOff() {
        store.meals = [
            Meal(name: "B", ingredients: [MealIngredient(name: "Eggs"), MealIngredient(name: "Ham"), MealIngredient(name: "Bread")]),
            Meal(name: "A", ingredients: [MealIngredient(name: "Eggs"), MealIngredient(name: "Bread")]),
        ]
        store.stock = [stock("Eggs", aisle: .dairy, daysLeft: 20)]
        XCTAssertEqual(store.mealsFromHome().map(\.meal.name), ["A", "B"])
    }

    func testAddingOnlyWhatsMissing() {
        store.meals = [Meal(name: "Salad", ingredients: [
            MealIngredient(name: "Spinach", aisle: .produce),
            MealIngredient(name: "Feta", aisle: .dairy, amount: 4, unit: "oz"),
        ])]
        store.stock = [stock("Spinach", daysLeft: 3)]
        let match = store.mealsFromHome()[0]
        XCTAssertEqual(store.addMissing(match, shopID: nil), 1)
        XCTAssertEqual(store.items.map(\.name), ["Feta"])
        XCTAssertEqual(store.items[0].note, "4 oz")
    }

    func testIdeasSkipWhatsAtHomeOrAlreadyListed() {
        store.stock = [stock("Lemons", daysLeft: 10)]
        store.items = [GroceryItem(name: "Rice")]
        XCTAssertEqual(store.addMissing(["Lemon", "Rice", "Garlic"], shopID: nil), 1)
        XCTAssertEqual(store.items.map(\.name), ["Rice", "Garlic"])
    }

    func testSavingAnIdeaMakesAMealAndPlansIt() {
        let idea = CookIdea(title: "Spinach Frittata", uses: ["Spinach", "Eggs"], extras: ["Feta"], summary: "Bake it.")
        let meal = store.saveIdea(idea, planOn: Date())
        XCTAssertEqual(store.meals.map(\.name), ["Spinach Frittata"])
        XCTAssertEqual(meal.ingredients.map(\.name), ["Spinach", "Eggs", "Feta"])
        XCTAssertEqual(store.planned(on: Date()).map(\.mealID), [meal.id])
        store.saveIdea(idea)
        XCTAssertEqual(store.plan.count, 1)
    }

    func testNothingAtHomeMeansNoMatches() {
        store.meals = [Meal(name: "Omelet", ingredients: [MealIngredient(name: "Eggs")])]
        XCTAssertTrue(store.mealsFromHome().isEmpty)
    }
}

final class ControlRequestTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = PendingAction.take()
    }

    func testARequestIsHandledOnce() {
        PendingAction.request(.startShopping)
        XCTAssertEqual(PendingAction.take(), .startShopping)
        XCTAssertNil(PendingAction.take())
    }

    func testTheLatestRequestWins() {
        PendingAction.request(.startShopping)
        PendingAction.request(.quickAdd)
        XCTAssertEqual(PendingAction.take(), .quickAdd)
    }

    func testRequestingPostsANotification() {
        let posted = expectation(forNotification: PendingAction.requested, object: nil)
        PendingAction.request(.quickAdd)
        wait(for: [posted], timeout: 1)
    }
}

final class PriceHistoryTests: StoreTestCase {
    private var kroger: Shop!, walmart: Shop!

    override func setUp() {
        super.setUp()
        kroger = store.addShop(named: "Kroger")!
        walmart = store.addShop(named: "Walmart")!
    }

    private func record(_ name: String, _ prices: [(Shop?, Double)]) {
        var past = PastItem(name: name, aisle: .other, shopID: nil, price: nil)
        past.priceHistory = prices.enumerated().map { i, entry in
            PricePoint(shopID: entry.0?.id, price: entry.1, date: day(i - prices.count))
        }
        store.history.append(past)
    }

    func testUsualPriceIgnoresOneOffs() {
        XCTAssertEqual(PriceTrend.median([3, 1, 2]), 2)
        XCTAssertEqual(PriceTrend.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(PriceTrend.median([]), 0)
        record("Milk", [(kroger, 4.00), (kroger, 4.10), (kroger, 9.99), (kroger, 4.05)])
        XCTAssertEqual(store.priceTrend(for: "milk")?.usual ?? 0, 4.075, accuracy: 0.001)
    }

    func testAPriceWellUnderUsualIsADeal() throws {
        record("Coffee", [(kroger, 10), (kroger, 10.5), (walmart, 10), (kroger, 7.99)])
        let trend = try XCTUnwrap(store.priceTrend(for: "Coffee"))
        XCTAssertEqual(trend.discount ?? 0, 0.2, accuracy: 0.01)
        XCTAssertEqual(store.priceDeals().map(\.name), ["Coffee"])
    }

    func testSmallDropsAndShortHistoriesAreNotDeals() {
        record("Eggs", [(kroger, 3.00), (kroger, 3.10), (kroger, 2.95)])
        record("Bread", [(kroger, 4.00), (kroger, 2.00)])
        XCTAssertNil(store.priceTrend(for: "Eggs")?.discount)
        XCTAssertNil(store.priceTrend(for: "Bread")?.discount)
        XCTAssertTrue(store.priceDeals().isEmpty)
    }

    func testCheapestStoreIsByAverage() throws {
        record("Butter", [(kroger, 5.00), (walmart, 4.00), (kroger, 5.20), (walmart, 4.40), (nil, 3.00)])
        let trend = try XCTUnwrap(store.priceTrend(for: "Butter"))
        XCTAssertEqual(trend.cheapestStore?.name, "Walmart")
        XCTAssertEqual(trend.cheapestStore?.average ?? 0, 4.20, accuracy: 0.001)
        XCTAssertEqual(trend.spread, 0.90, accuracy: 0.001)
        XCTAssertEqual(trend.stores.count, 3)
        XCTAssertEqual(store.cheapestStores().map(\.name), ["Butter"])
    }

    func testOneStoreOrOnePriceGivesNoComparison() {
        record("Salt", [(kroger, 1.00)])
        record("Rice", [(kroger, 2.00), (kroger, 2.20)])
        XCTAssertNil(store.priceTrend(for: "Salt"))
        XCTAssertNil(store.priceTrend(for: "Rice")?.cheapestStore)
        XCTAssertTrue(store.cheapestStores().isEmpty)
        XCTAssertNil(store.priceTrend(for: "Unknown"))
    }

    func testDeletedStoresCountAsNoStore() throws {
        record("Tea", [(kroger, 3.00), (walmart, 2.50)])
        store.deleteShop(walmart)
        let trend = try XCTUnwrap(store.priceTrend(for: "Tea"))
        XCTAssertEqual(Set(trend.stores.map(\.name)), ["Kroger", "No store"])
    }
}

final class HouseholdSyncTests: StoreTestCase {
    /// The other phone's list, packed and sent through bytes the way it crosses the network. (A second
    /// GroceryStore would share this test's files, so the packet is built by hand.)
    private func packet(_ items: [GroceryItem], removed: [UUID] = [], unchecked: [UUID] = []) throws -> SyncPacket {
        let list = ListExport(from: "Sam", items: items.map {
            .init(id: $0.id, name: $0.name, quantity: $0.quantity, aisle: $0.aisle, isChecked: $0.isChecked,
                  shopName: nil, price: $0.price, note: $0.note)
        })
        let sent = SyncPacket(from: "Sam", list: list, removed: removed, unchecked: unchecked)
        return try XCTUnwrap(SyncPacket.decode(sent.encoded()))
    }

    func testOwnPacketCarriesTheWholeList() {
        store.items = [GroceryItem(name: "Milk"), GroceryItem(name: "Eggs")]
        let own = store.makeSyncPacket(from: "Me", removed: [store.items[0].id])
        XCTAssertEqual(own.list.items.map(\.name), ["Milk", "Eggs"])
        XCTAssertEqual(own.removed, [store.items[0].id])
        XCTAssertEqual(own.from, "Me")
    }

    func testCodesMatchLooselyAndAreNeverBroadcast() {
        XCTAssertEqual(HouseholdCode.normalized("Maple 42"), HouseholdCode.normalized("maple-42"))
        XCTAssertEqual(HouseholdCode.tag(for: "Maple 42"), HouseholdCode.tag(for: "maple-42"))
        XCTAssertNotEqual(HouseholdCode.tag(for: "maple-42"), HouseholdCode.tag(for: "maple-43"))
        XCTAssertFalse(HouseholdCode.tag(for: "maple-42").contains("maple"))
        XCTAssertTrue(HouseholdCode.isValid("pear-4821"))
        XCTAssertFalse(HouseholdCode.isValid("a-b"))
        XCTAssertTrue(HouseholdCode.isValid(HouseholdCode.random()))
    }

    func testNewItemsAndCheckOffsArrive() throws {
        let milk = GroceryItem(name: "Milk", aisle: .dairy)
        store.items = [milk]
        var theirMilk = milk
        theirMilk.isChecked = true
        let summary = store.applySyncPacket(try packet([theirMilk, GroceryItem(name: "Eggs", aisle: .dairy)]))
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.markedBought, 1)
        XCTAssertEqual(store.items.map(\.name), ["Milk", "Eggs"])
        XCTAssertTrue(store.items[0].isChecked)
    }

    func testRemovalsAndUnchecksArrive() throws {
        var bread = GroceryItem(name: "Bread")
        bread.isChecked = true
        let soap = GroceryItem(name: "Soap")
        store.items = [bread, soap]
        var theirBread = bread
        theirBread.isChecked = false
        store.applySyncPacket(try packet([theirBread], removed: [soap.id], unchecked: [bread.id]))
        XCTAssertEqual(store.items.map(\.name), ["Bread"])
        XCTAssertFalse(store.items[0].isChecked)
    }

    func testClearedItemsDontComeBack() throws {
        var done = GroceryItem(name: "Bananas")
        done.isChecked = true
        // We cleared it; the other phone still has it checked off.
        store.items = []
        XCTAssertEqual(store.applySyncPacket(try packet([done])).added, 0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testAnUncheckHereIsntUndoneByAnOlderCheckThere() throws {
        var coffee = GroceryItem(name: "Coffee")
        coffee.isChecked = true
        store.items = [GroceryItem(name: "Coffee")]
        store.items[0].id = coffee.id
        store.applySyncPacket(try packet([coffee], unchecked: [coffee.id]))
        XCTAssertFalse(store.items[0].isChecked)
    }

    func testApplyingTheSamePacketTwiceChangesNothing() throws {
        let rice = GroceryItem(name: "Rice")
        let incoming = try packet([rice])
        store.applySyncPacket(incoming)
        let after = store.items
        XCTAssertEqual(store.applySyncPacket(incoming).added, 0)
        XCTAssertEqual(store.items, after)
        XCTAssertEqual(incoming, try packet([rice]))
    }

    func testTrackerNoticesRemovalsAndUnchecks() {
        var a = GroceryItem(name: "A"), b = GroceryItem(name: "B")
        a.isChecked = true
        var tracker = SyncTracker(items: [a, b])
        var reopened = a
        reopened.isChecked = false
        let first = tracker.changes(in: [reopened])
        XCTAssertEqual(first.removed, [b.id])
        XCTAssertEqual(first.unchecked, [a.id])
        let second = tracker.changes(in: [reopened])
        XCTAssertTrue(second.removed.isEmpty)
        XCTAssertTrue(second.unchecked.isEmpty)
    }

    func testGarbledPacketsAreIgnored() {
        XCTAssertNil(SyncPacket.decode(Data("not json".utf8)))
    }
}

final class SpotlightTests: StoreTestCase {
    func testMealsItemsAndPastPurchasesAreSearchable() {
        let kroger = store.addShop(named: "Kroger")!
        store.meals = [Meal(name: "Lasagna", ingredients: [MealIngredient(name: "Ricotta"), MealIngredient(name: "Noodles")])]
        store.items = [GroceryItem(name: "Milk", aisle: .dairy, shopID: kroger.id, note: "2%")]
        store.history = [PastItem(name: "Milk", aisle: .dairy, shopID: kroger.id, price: 3.49),
                         PastItem(name: "Coffee", aisle: .drinks, shopID: kroger.id, price: 8.99)]
        let entries = store.spotlightEntries()
        XCTAssertEqual(entries.map(\.title), ["Lasagna", "Milk", "Coffee"])
        XCTAssertEqual(entries[0].detail, "Meal: Ricotta and Noodles")
        XCTAssertTrue(entries[0].keywords.contains("Ricotta"))
        XCTAssertEqual(entries[1].detail, "On your list at Kroger · 2%")
        XCTAssertTrue(entries[2].detail.hasPrefix("Not on your list · last at Kroger · "))
    }

    func testCheckedItemsAndUntitledMealsReadClearly() {
        var bread = GroceryItem(name: "Bread")
        bread.isChecked = true
        store.items = [bread]
        store.meals = [Meal(name: "")]
        let entries = store.spotlightEntries()
        XCTAssertEqual(entries[0].title, "Untitled meal")
        XCTAssertEqual(entries[0].detail, "Saved meal")
        XCTAssertEqual(entries[1].detail, "Checked off")
    }

    func testIdsSayWhatToOpen() {
        let id = UUID().uuidString
        let entry = SpotlightEntry(kind: .item, key: id, title: "Milk", detail: "", keywords: [])
        XCTAssertEqual(SpotlightEntry.parse(entry.id)?.kind, .item)
        XCTAssertEqual(SpotlightEntry.parse(entry.id)?.key, id)
        XCTAssertEqual(SpotlightEntry.parse("past:Peanut butter: crunchy")?.key, "Peanut butter: crunchy")
        XCTAssertNil(SpotlightEntry.parse("meal:"))
        XCTAssertNil(SpotlightEntry.parse("other:thing"))
        XCTAssertNil(SpotlightEntry.parse("nocolon"))
    }
}

final class ShoppingProgressTests: XCTestCase {
    private func item(_ name: String, _ aisle: Aisle, checked: Bool = false) -> GroceryItem {
        var item = GroceryItem(name: name, aisle: aisle)
        item.isChecked = checked
        return item
    }

    func testNextAisleFollowsTheWalkingOrder() {
        let items = [item("Milk", .dairy), item("Eggs", .dairy), item("Bread", .bakery, checked: true), item("Apples", .produce)]
        let progress = ShoppingProgress(items: items, order: [.bakery, .dairy, .produce],
                                        label: { $0 == .dairy ? "Aisle 9" : nil })
        XCTAssertEqual(progress.inCart, 1)
        XCTAssertEqual(progress.total, 4)
        XCTAssertEqual(progress.remaining, 3)
        XCTAssertEqual(progress.fraction, 0.25)
        XCTAssertEqual(progress.nextAisle, .dairy)
        XCTAssertEqual(progress.leftInNextAisle, 2)
        XCTAssertEqual(progress.nextText, "Next: Dairy & Eggs, Aisle 9 · 2 items")
        XCTAssertFalse(progress.isDone)
    }

    func testAnAisleMissingFromTheOrderStillComesUp() {
        let progress = ShoppingProgress(items: [item("Soap", .household)], order: [.produce])
        XCTAssertEqual(progress.nextAisle, .household)
        XCTAssertEqual(progress.nextText, "Next: Household · 1 item")
    }

    func testDoneOnlyWhenEverythingIsInTheCart() {
        let done = ShoppingProgress(items: [item("Milk", .dairy, checked: true)], order: Aisle.allCases)
        XCTAssertTrue(done.isDone)
        XCTAssertNil(done.nextText)
        XCTAssertEqual(done.fraction, 1)
        let empty = ShoppingProgress(items: [], order: Aisle.allCases)
        XCTAssertFalse(empty.isDone)
        XCTAssertEqual(empty.fraction, 0)
    }
}

final class FirstLaunchTests: StoreTestCase {
    func testAFreshStoreIsAFirstRun() {
        // StoreTestCase deletes every saved file before making the store.
        XCTAssertTrue(store.isFirstRun)
        store.items = [GroceryItem(name: "Milk")]
        XCTAssertFalse(GroceryStore().isFirstRun, "once the list is saved, the next launch isn't")
    }

    func testSetupKeepsThePickedStoresInOrder() {
        store.items = [GroceryItem(name: "Bananas")]
        store.history = [PastItem(name: "Bananas", aisle: .produce, shopID: nil, price: nil)]
        store.finishSetup(storeNames: ["Costco", " Aldi ", "costco", "", "Corner Shop"], keepSample: true)
        XCTAssertEqual(store.shops.map(\.name), ["Costco", "Aldi", "Corner Shop", "Online"], "everyone gets an Online chip")
        XCTAssertEqual(store.items.map(\.name), ["Bananas"])
        XCTAssertFalse(store.isFirstRun)
    }

    func testStartingEmptyClearsTheSampleItems() {
        store.items = [GroceryItem(name: "Bananas")]
        store.history = [PastItem(name: "Bananas", aisle: .produce, shopID: nil, price: nil)]
        store.finishSetup(storeNames: [], keepSample: false)
        XCTAssertEqual(store.shops.map(\.name), ["Online"])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
    }
}

final class FirstLaunchSafetyTests: StoreTestCase {
    func testAMissingListAloneIsNotAFirstRun() {
        store.items = [GroceryItem(name: "Milk")]
        store.shops = [Shop(name: "Kroger")]
        store.history = [PastItem(name: "Milk", aisle: .dairy, shopID: nil, price: nil)]
        try? FileManager.default.removeItem(at: Storage.url("grocery"))
        XCTAssertFalse(GroceryStore().isFirstRun, "stores and history are still there, so this isn't a fresh install")
    }
}

final class PharmacyAisleTests: StoreTestCase {
    func testStoresSavedBeforePharmacyGetItJustBeforeOther() {
        var shop = Shop(name: "Kroger")
        shop.aisleOrder = [.bakery, .produce, .dairy, .meat, .pantry, .frozen, .drinks, .household, .other]
        XCTAssertEqual(Array(shop.orderedAisles.suffix(2 + Aisle.nonFood.count + 1)), [.household, .pharmacy] + Aisle.nonFood + [.other])
        XCTAssertEqual(shop.orderedAisles.count, Aisle.allCases.count)
    }

    func testAnOrderNotEndingInOtherStillGetsPharmacy() {
        var shop = Shop(name: "Walmart")
        shop.aisleOrder = [.other, .produce]
        XCTAssertEqual(Array(shop.orderedAisles.prefix(2)), [.other, .produce])
        XCTAssertTrue(shop.orderedAisles.contains(.pharmacy))
        XCTAssertEqual(shop.orderedAisles.count, Aisle.allCases.count)
    }

    func testOldStoresStillDecodeAndNewOnesListPharmacy() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Kroger","aisleOrder":["Produce","Household","Other"]}"#
        let shop = try JSONDecoder().decode(Shop.self, from: Data(old.utf8))
        XCTAssertEqual(Array(shop.orderedAisles.prefix(2)), [.produce, .household])
        XCTAssertEqual(shop.orderedAisles.last, .other)
        XCTAssertTrue(Shop(name: "New").orderedAisles.contains(.pharmacy))
    }

    func testMedicineAndToiletriesAreFiledInPharmacy() {
        for name in ["Ibuprofen", "Vitamin D", "Toothpaste", "Band-aid bandages", "Sunscreen SPF 50", "Shampoo"] {
            XCTAssertEqual(Aisle.guess(fromCategories: [name]), .pharmacy, name)
        }
        XCTAssertEqual(Aisle.guess(fromCategories: ["Pillsbury cookie dough"]), .pantry)
        XCTAssertEqual(Aisle.guess(fromCategories: ["Orange juice"]), .drinks)
        store.addOrBump(name: "Advil", shopID: nil)
        XCTAssertEqual(store.items.first?.aisle, .pharmacy)
    }
}

final class CloudMergeTests: StoreTestCase {
    private func data<T: Encodable>(_ value: [T]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try! encoder.encode(value)
    }

    func testFirstSyncCombinesAndDeletesNothing() {
        let milk = GroceryItem(name: "Milk"), eggs = GroceryItem(name: "Eggs")
        store.items = [milk]
        let merged = store.applyCloudCopy(name: "grocery", remote: data([eggs]), base: nil)
        XCTAssertEqual(Set(store.items.map(\.name)), ["Milk", "Eggs"])
        XCTAssertNotEqual(merged, data([eggs]), "the phone had Milk, which iCloud needs")
    }

    func testDeletionsAndEditsFromAnotherDeviceArrive() {
        let milk = GroceryItem(name: "Milk"), eggs = GroceryItem(name: "Eggs")
        store.items = [milk, eggs]
        let base = data([milk, eggs])
        var boughtEggs = eggs
        boughtEggs.isChecked = true
        // The other device deleted Milk and checked off Eggs.
        let merged = store.applyCloudCopy(name: "grocery", remote: data([boughtEggs]), base: base)
        XCTAssertEqual(store.items.map(\.name), ["Eggs"])
        XCTAssertTrue(store.items[0].isChecked)
        XCTAssertEqual(merged, data([boughtEggs]), "nothing new here to send back")
    }

    func testChangesOnBothDevicesAreKept() {
        let milk = GroceryItem(name: "Milk")
        store.items = [milk, GroceryItem(name: "Bread")]
        let base = data([milk])
        store.applyCloudCopy(name: "grocery", remote: data([milk, GroceryItem(name: "Coffee")]), base: base)
        XCTAssertEqual(Set(store.items.map(\.name)), ["Milk", "Bread", "Coffee"])
    }

    func testEveryFileRoundTrips() {
        store.items = [GroceryItem(name: "Milk")]
        _ = store.addShop(named: "Kroger")
        store.addFavorite(name: "Coffee")
        store.meals = [Meal(name: "Tacos")]
        store.history = [PastItem(name: "Milk", aisle: .dairy, shopID: nil, price: 3.49)]
        store.setRepeat(for: store.items[0], everyDays: 7)
        store.addPlan(store.meals[0], on: Date())
        store.stock = [StockEntry(name: "Milk", aisle: .dairy, bought: Date(), expires: Date())]
        store.recordSpend(amount: 20, shopID: nil)
        for name in GroceryStore.cloudFileNames {
            let copy = try! XCTUnwrap(store.cloudData(for: name), name)
            XCTAssertEqual(store.applyCloudCopy(name: name, remote: copy, base: copy), copy, name)
        }
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.cloudData(for: "unknown"))
        XCTAssertNil(store.applyCloudCopy(name: "unknown", remote: Data(), base: nil))
    }

    func testAnUnreadableCopyChangesNothing() {
        store.items = [GroceryItem(name: "Milk")]
        XCTAssertNil(store.applyCloudCopy(name: "grocery", remote: Data("not a list".utf8), base: nil))
        // A newer app's aisle this version doesn't know.
        let future = #"[{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"X","quantity":1,"aisle":"Deli","isChecked":false}]"#
        XCTAssertNil(store.applyCloudCopy(name: "grocery", remote: Data(future.utf8), base: nil))
        XCTAssertEqual(store.items.map(\.name), ["Milk"])
    }

    func testChangedFilesAreThoseThatDifferFromTheBaseline() {
        var baseline = CloudBaseline(folder: nil)
        store.items = [GroceryItem(name: "Milk")]
        XCTAssertEqual(store.cloudFilesChanged(since: baseline), GroceryStore.cloudFileNames)
        for name in GroceryStore.cloudFileNames { baseline[name] = store.cloudData(for: name) }
        XCTAssertTrue(store.cloudFilesChanged(since: baseline).isEmpty)
        store.items.append(GroceryItem(name: "Eggs"))
        XCTAssertEqual(store.cloudFilesChanged(since: baseline), ["grocery"])
        baseline.reset()
        XCTAssertNil(baseline["grocery"])
    }

    func testTheBaselineIsKeptOnDisk() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "baseline-\(UUID().uuidString)", directoryHint: .isDirectory)
        var baseline = CloudBaseline(folder: folder)
        baseline["grocery"] = Data("[1]".utf8)
        XCTAssertEqual(CloudBaseline(folder: folder)["grocery"], Data("[1]".utf8))
        baseline.reset()
        XCTAssertNil(CloudBaseline(folder: folder)["grocery"])
    }

    func testEveryChangeBumpsTheRevision() {
        let before = store.revision
        store.items.append(GroceryItem(name: "Milk"))
        store.meals.append(Meal(name: "Tacos"))
        XCTAssertGreaterThanOrEqual(store.revision, before + 2)
    }
}
