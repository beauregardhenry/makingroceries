import XCTest

final class MealCategoryTests: StoreTestCase {
    func testNamesAreGuessedIntoCategories() {
        XCTAssertEqual(MealCategory.guess(fromName: "Chicken Noodle Soup"), .soup)
        XCTAssertEqual(MealCategory.guess(fromName: "Blueberry Pancakes"), .breakfast)
        XCTAssertEqual(MealCategory.guess(fromName: "Chocolate Chip Cookies"), .dessert)
        XCTAssertEqual(MealCategory.guess(fromName: "Mango Smoothie"), .drink)
        XCTAssertEqual(MealCategory.guess(fromName: "Spinach Dip"), .snack)
        XCTAssertEqual(MealCategory.guess(fromName: "Coleslaw"), .side)
        XCTAssertEqual(MealCategory.guess(fromName: "Turkey Sandwich"), .lunch)
        XCTAssertNil(MealCategory.guess(fromName: "Grandma's Thing"))
    }

    func testAMealShowsItsOwnCategoryOrAGuess() {
        var meal = Meal(name: "Beef Chili")
        XCTAssertEqual(meal.shownCategory, .soup)
        meal.category = .dinner
        XCTAssertEqual(meal.shownCategory, .dinner)
        XCTAssertEqual(Meal(name: "Mystery").shownCategory, .dinner, "unknown names default to dinner")
    }

    func testMealsSavedBeforeCategoriesStillDecode() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Pasta","ingredients":[]}"#
        let meal = try JSONDecoder().decode(Meal.self, from: Data(old.utf8))
        XCTAssertNil(meal.category)
        XCTAssertFalse(meal.freezerFriendly)
    }

    func testEveryCategoryHasASymbolAndColor() {
        XCTAssertEqual(Set(MealCategory.allCases.map(\.symbol)).count, MealCategory.allCases.count)
    }
}

final class TravelItemTests: StoreTestCase {
    func testTripItemsAreKeptSeparateFromTheSameItemOnTheList() {
        store.addOrBump(name: "Sunscreen", shopID: nil)
        store.addOrBump(name: "Sunscreen", shopID: nil, travel: true)
        XCTAssertEqual(store.items.count, 2, "a trip item doesn't merge into the everyday one")
        store.addOrBump(name: "Sunscreen", shopID: nil, travel: true)
        XCTAssertEqual(store.items.filter(\.forTravel).first?.quantity, 2)
        XCTAssertEqual(store.items.filter { !$0.forTravel }.first?.quantity, 1)
    }

    func testTripItemsStayOffTheWidgetAndWatch() {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        store.add(name: "Phone charger", quantity: 1, aisle: .electronics, travel: true)
        XCTAssertEqual(store.widgetItems(shopID: nil).map(\.name), ["Milk"])
        XCTAssertEqual(store.watchSnapshot().groups.flatMap(\.items).map(\.name), ["Milk"])
    }

    func testTravelIsAFilterThatSurvivesARestart() {
        XCTAssertEqual(ShopFilter(raw: ShopFilter.travel.raw), .travel)
        XCTAssertEqual(ShopFilter(raw: "any"), .anyStore)
        XCTAssertEqual(ShopFilter(raw: ""), .all)
    }

    func testItemsSavedBeforeTravelAreNotForTravel() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Milk","quantity":1,"aisle":"Dairy & Eggs","isChecked":false}"#
        let item = try JSONDecoder().decode(GroceryItem.self, from: Data(old.utf8))
        XCTAssertFalse(item.forTravel)
    }
}

final class NonFoodStoreTests: StoreTestCase {
    func testHardwareAndHomeItemsAreFiledInTheirOwnAisles() {
        let expected: [(String, Aisle)] = [
            ("Hammer", .hardware), ("Paint", .hardware), ("Light bulbs", .hardware), ("AA batteries", .hardware),
            ("Potting soil", .garden), ("Lawn mower", .garden), ("Garden hose", .garden),
            ("USB charger", .electronics), ("HDMI cable", .electronics),
            ("Socks", .clothing), ("T-shirt", .clothing),
            ("Throw pillow", .home), ("Curtains", .home),
            ("Dog kibble", .pet), ("Cat litter", .pet),
            ("Lego set", .toys), ("Puzzle", .toys),
        ]
        for (name, aisle) in expected {
            XCTAssertEqual(Aisle.guess(fromCategories: [name]), aisle, name)
        }
    }

    func testFoodIsNotMistakenForTools() {
        XCTAssertEqual(Aisle.guess(fromCategories: ["Ham"]), .meat)
        XCTAssertEqual(Aisle.guess(fromCategories: ["Salad dressing"]), .produce)
        XCTAssertEqual(Aisle.guess(fromCategories: ["Paper towels"]), .household)
        XCTAssertEqual(Aisle.guess(fromCategories: ["Orange juice"]), .drinks)
    }

    func testWellKnownStoresGetTheRightType() {
        XCTAssertEqual(Shop.kind(forName: "Home Depot"), .hardware)
        XCTAssertEqual(Shop.kind(forName: "Lowe's"), .hardware)
        XCTAssertEqual(Shop.kind(forName: "Target"), .general)
        XCTAssertEqual(Shop.kind(forName: "Walmart Supercenter"), .general)
        XCTAssertNil(Shop.kind(forName: "Kroger"))
        XCTAssertEqual(Shop.presetNames.filter { Shop.kind(forName: $0) == .hardware }.count, 4)
    }

    func testAddingAHardwareStoreOrdersItsAislesToolsFirst() throws {
        let shop = try XCTUnwrap(store.addShop(named: "Home Depot"))
        XCTAssertEqual(shop.kind, .hardware)
        XCTAssertEqual(shop.orderedAisles.first, .hardware)
        XCTAssertEqual(shop.orderedAisles.last, .other)
        XCTAssertEqual(Set(shop.orderedAisles), Set(Aisle.allCases))
        XCTAssertEqual(shop.orderedAisles, shop.defaultOrder)
    }

    func testAGeneralStoreWalksFoodBeforeNonFood() throws {
        let shop = try XCTUnwrap(store.addShop(named: "Target"))
        let order = shop.orderedAisles
        let lastFood = try XCTUnwrap(order.lastIndex { $0.isFood && $0 != .other })
        let firstNonFood = try XCTUnwrap(order.firstIndex { !$0.isFood })
        XCTAssertLessThan(lastFood, firstNonFood)
        XCTAssertEqual(order.last, .other)
    }

    func testAGroceryStoreKeepsTheDefaultOrderAndNoType() throws {
        let shop = try XCTUnwrap(store.addShop(named: "Kroger"))
        XCTAssertNil(shop.kind)
        XCTAssertEqual(shop.orderedAisles, Aisle.allCases)
        XCTAssertEqual(ShopKind.allCases.map(\.title).count, 3)
    }

    func testStoreTypeSurvivesSavingAndOldStoresStillLoad() throws {
        let shop = Shop(name: "Lowe's", kind: .hardware)
        let again = try JSONDecoder().decode(Shop.self, from: JSONEncoder().encode(shop))
        XCTAssertEqual(again.kind, .hardware)
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Kroger"}"#
        XCTAssertNil(try JSONDecoder().decode(Shop.self, from: Data(old.utf8)).kind)
    }

    func testNonFoodAislesAreNotFood() {
        XCTAssertEqual(Aisle.nonFood.count, 7)
        XCTAssertTrue(Aisle.nonFood.allSatisfy { !$0.isFood })
        XCTAssertTrue(Aisle.produce.isFood)
    }
}

final class MakeAheadTests: StoreTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testCompanyEventsAreRecognizedByTitleOrGuestCount() {
        func event(_ title: String, guests: Int = 0, allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: title, title: title, start: Date(), attendeeCount: guests, isAllDay: allDay)
        }
        XCTAssertTrue(CompanyEvents.looksLikeCompany(event("Dinner with the Hendersons")))
        XCTAssertTrue(CompanyEvents.looksLikeCompany(event("Emma's BIRTHDAY")))
        XCTAssertTrue(CompanyEvents.looksLikeCompany(event("Game night", guests: 6)))
        XCTAssertFalse(CompanyEvents.looksLikeCompany(event("Dentist")))
        XCTAssertFalse(CompanyEvents.looksLikeCompany(event("Team standup", guests: 3)))
        XCTAssertTrue(CompanyEvents.looksLikeCompany(event("Company offsite", guests: 2, allDay: true)),
                      "the word company counts even on an all-day event")
        XCTAssertFalse(CompanyEvents.looksLikeCompany(event("Conference", guests: 40, allDay: true)))
    }

    func testOnlyUpcomingCompanyEventsComeBackSoonestFirst() {
        let now = date(2026, 11, 7)
        let events = [
            CalendarEvent(id: "a", title: "Thanksgiving dinner", start: date(2026, 11, 26)),
            CalendarEvent(id: "b", title: "Dentist", start: date(2026, 11, 10)),
            CalendarEvent(id: "c", title: "Birthday party", start: date(2026, 11, 14)),
            CalendarEvent(id: "d", title: "Old dinner", start: date(2026, 11, 1)),
            CalendarEvent(id: "e", title: "Brunch far away", start: date(2027, 3, 1)),
        ]
        XCTAssertEqual(CompanyEvents.upcoming(events, from: now, days: 21).map(\.id), ["c", "a"])
    }

    func testMakeByIsAFewDaysBeforeButNeverInThePast() {
        let now = date(2026, 11, 7)
        let early = MakeAhead.makeByDate(for: date(2026, 11, 20), now: now)
        XCTAssertEqual(early, Calendar.current.startOfDay(for: date(2026, 11, 17)))
        let soon = MakeAhead.makeByDate(for: date(2026, 11, 8), now: now)
        XCTAssertEqual(soon, Calendar.current.startOfDay(for: now), "company tomorrow means cook today")
    }

    func testBatchSizeFollowsTheGuestCount() {
        XCTAssertEqual(MakeAhead.scale(forGuests: 4), 1)
        XCTAssertEqual(MakeAhead.scale(forGuests: 8), 2)
        XCTAssertEqual(MakeAhead.scale(forGuests: 6), 1.5)
        XCTAssertEqual(MakeAhead.scale(forGuests: 1), 0.5)
        XCTAssertEqual(MakeAhead.scale(forGuests: 0), 0.5)
    }

    func testYourFreezerMealsComeBeforeTheBuiltInIdeasWithoutRepeats() {
        var mine = Meal(name: "Grandma's Casserole", ingredients: [MealIngredient(name: "Noodles")])
        mine.freezes = true
        let lasagna = { var m = Meal(name: "lasagna"); m.freezes = true; return m }()
        let notFrozen = Meal(name: "Fresh salad")
        let ideas = MakeAhead.suggestions(meals: [mine, lasagna, notFrozen])
        XCTAssertEqual(ideas.first?.title, "Grandma's Casserole")
        XCTAssertEqual(ideas.first?.mealID, mine.id)
        XCTAssertEqual(ideas.filter { $0.title.lowercased() == "lasagna" }.count, 1, "a saved lasagna replaces the built-in one")
        XCTAssertFalse(ideas.contains { $0.title == "Fresh salad" })
        XCTAssertEqual(MakeAhead.suggestions(meals: [], limit: 3).count, 3)
        XCTAssertEqual(Set(MakeAhead.builtIn.map(\.id)).count, MakeAhead.builtIn.count)
    }

    func testPlanningAMakeAheadDishSavesItAndPlansItBeforeTheEvent() throws {
        let now = date(2026, 11, 7)
        let idea = try XCTUnwrap(MakeAhead.builtIn.first { $0.title == "Beef Chili" })
        let meal = store.planMakeAhead(idea, for: date(2026, 11, 20), now: now)
        XCTAssertTrue(meal.freezerFriendly)
        XCTAssertEqual(meal.category, .soup)
        XCTAssertEqual(meal.ingredients.count, idea.ingredients.count)
        XCTAssertEqual(store.meals.count, 1)
        XCTAssertEqual(store.plan.first?.day, Calendar.current.startOfDay(for: date(2026, 11, 17)))
        // Planning it again reuses the saved meal.
        store.planMakeAhead(idea, for: date(2026, 11, 25), now: now)
        XCTAssertEqual(store.meals.count, 1)
        XCTAssertEqual(store.plan.count, 2)
    }

    func testMakeAheadIngredientsGoOnTheListScaledForGuests() throws {
        let idea = try XCTUnwrap(MakeAhead.builtIn.first { $0.title == "Meatballs" })
        store.addMakeAheadToList(idea, shopID: nil, scale: 2)
        XCTAssertEqual(store.items.count, idea.ingredients.count)
        XCTAssertTrue(store.items.allSatisfy { $0.quantity == 2 })
        XCTAssertEqual(store.meals.count, 1)
    }

    func testASavedMealIsReusedByItsID() {
        var meal = Meal(name: "Mine")
        meal.freezes = true
        store.meals = [meal]
        let idea = MakeAhead.suggestions(meals: store.meals)[0]
        XCTAssertEqual(store.makeAheadMeal(for: idea).id, meal.id)
        XCTAssertEqual(store.meals.count, 1)
    }
}

final class ChipOrderTests: XCTestCase {
    private let shops = [Shop(name: "Kroger"), Shop(name: "Walmart"), Shop(name: "Aldi")]

    func testTravelIsLastUntilYouMoveIt() {
        let entries = ChipOrder.entries(shops: shops, travelPosition: ChipOrder.last)
        XCTAssertEqual(entries.last, .travel)
        XCTAssertEqual(entries.count, 4)
    }

    func testTravelSitsWhereYouPutIt() {
        let entries = ChipOrder.entries(shops: shops, travelPosition: 1)
        XCTAssertEqual(entries[1], .travel)
        XCTAssertEqual(entries[0], .shop(shops[0].id))
        XCTAssertEqual(entries[2], .shop(shops[1].id))
    }

    func testAPositionPastTheEndStillShowsTravel() {
        XCTAssertEqual(ChipOrder.entries(shops: shops, travelPosition: 99).last, .travel)
        XCTAssertEqual(ChipOrder.entries(shops: [], travelPosition: 2), [.travel])
    }

    func testMovingChipsSavesBothTheStoreOrderAndTravelsPlace() {
        var arranged = ChipOrder.entries(shops: shops, travelPosition: ChipOrder.last)
        arranged.move(fromOffsets: [3], toOffset: 0)   // Travel to the front
        XCTAssertEqual(ChipOrder.position(of: arranged), 0)
        arranged.move(fromOffsets: [2], toOffset: 0)   // then Walmart ahead of it
        XCTAssertEqual(ChipOrder.shops(shops, arrangedBy: arranged).map(\.name), ["Walmart", "Kroger", "Aldi"])
        XCTAssertEqual(ChipOrder.position(of: arranged), 1)
    }

    func testTravelMovedToTheEndStaysLastWhenStoresAreAdded() {
        var arranged = ChipOrder.entries(shops: shops, travelPosition: 0)
        arranged.move(fromOffsets: [0], toOffset: 4)
        XCTAssertEqual(ChipOrder.position(of: arranged), ChipOrder.last)
    }
}
