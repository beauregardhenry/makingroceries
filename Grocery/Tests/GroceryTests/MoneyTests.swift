import XCTest

final class UnitPriceTests: XCTestCase {
    private func size(_ text: String) -> String {
        SizeParser.parse(text).map { SizeParser.label($0.amount, $0.unit) } ?? "nil"
    }

    func testSizeParsing() {
        XCTAssertEqual(size("16 oz"), "16 oz")
        XCTAssertEqual(size("500 g"), "500 g")
        XCTAssertEqual(size("1.5 L"), "1.5 l")
        XCTAssertEqual(size("12 ct"), "12 ct")
        XCTAssertEqual(size("2 x 250 g"), "500 g")
        XCTAssertEqual(size("12 fl oz"), "12 fl oz")
        XCTAssertEqual(size("1 gallon"), "1 gal")
        XCTAssertEqual(size("fresh and tasty"), "nil")
    }

    func testPricePerUnit() throws {
        let big = try XCTUnwrap(UnitPrice.perUnit(price: 4.48, amount: 2, unit: "lb"))
        let small = try XCTUnwrap(UnitPrice.perUnit(price: 1.29, amount: 6, unit: "oz"))
        XCTAssertEqual(big.value, 0.14, accuracy: 0.001)
        XCTAssertEqual(big.label, "oz")
        XCTAssertGreaterThan(small.value, big.value)
        XCTAssertEqual(UnitPrice.text(price: 3.49, amount: 1, unit: "gal"), "$0.03/fl oz")
        XCTAssertNil(UnitPrice.perUnit(price: 5, amount: 0, unit: "oz"))
    }

    func testPriceFormattingAndParsing() {
        XCTAssertEqual(Price.parse("$3,49"), 3.49)
        XCTAssertEqual(Price.parse("3"), 3)
        XCTAssertNil(Price.parse("abc"))
        XCTAssertEqual(Price.editText(4.5), "4.50")
        XCTAssertEqual(Price.editText(nil), "")
    }

    func testTotalsCountOnlyPricedItems() {
        let totals = Totals([GroceryItem(name: "A", quantity: 2, price: 1.5), GroceryItem(name: "B")])
        XCTAssertEqual(totals.sum, 3.0)
        XCTAssertEqual(totals.priced, 1)
        XCTAssertEqual(totals.count, 2)
    }
}

final class ReceiptTests: XCTestCase {
    private func summary(_ entries: [ReceiptEntry]) -> [String] {
        entries.map { "\($0.name)|\($0.quantity)x\($0.unitPrice)=\($0.total)" }
    }

    func testParsesItemsAndSkipsNoise() {
        let rows = ["KROGER", "123 MAIN ST 555-0100", "4011 BANANAS  1.74", "6 @ 0.29", "BNLS CHKN THIGH  7.99",
                    "MILK 2% GAL  3.49 F", "BABY SPINACH 3.99", "COUPON -0.50", "SUBTOTAL 17.71", "TAX 0.00",
                    "TOTAL 17.71", "VISA ****1234  17.71", "THANK YOU"]
        let entries = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(entries.map(\.name), ["Bananas", "Bnls Chkn Thigh", "Milk 2% Gal", "Baby Spinach"])
        XCTAssertEqual(entries[0].quantity, 6)
        XCTAssertEqual(entries[0].unitPrice, 0.29)
        XCTAssertEqual(entries[0].total, 1.74, accuracy: 0.001)
        XCTAssertEqual(entries[2].total, 3.49)
    }

    func testTotalLine() {
        XCTAssertEqual(ReceiptParser.total(rows: ["BANANAS 1.74", "SUBTOTAL 24.60", "TAX 1.20", "TOTAL 25.80"]), 25.80)
        XCTAssertNil(ReceiptParser.total(rows: ["MILK 3.49"]))
        XCTAssertEqual(ReceiptParser.total(rows: ["TOTAL SAVINGS 4.00", "TOTAL 20.00"]), 20.00)
    }

    private let items = ["Bananas", "Chicken thighs", "Milk", "Baby spinach", "Cheddar", "Peanut butter", "Rice"]
        .map { GroceryItem(name: $0) }

    private func match(_ name: String) -> String? {
        ReceiptMatcher.bestMatch(for: ReceiptEntry(name: name, unitPrice: 1, total: 1), in: items)?.name
    }

    func testMatchingHandlesAbbreviations() {
        XCTAssertEqual(match("Bananas"), "Bananas")
        XCTAssertEqual(match("Bnls Chkn Thigh"), "Chicken thighs")
        XCTAssertEqual(match("Milk 2% Gal"), "Milk")
        XCTAssertEqual(match("Pnut Butter"), "Peanut butter")
        XCTAssertEqual(match("Bananas Organic"), "Bananas")
    }

    func testMatchingAvoidsLookAlikes() {
        XCTAssertNil(match("Ricotta"))
        XCTAssertNil(match("Bread"))
    }

    func testExactnessFlagsExtraWords() {
        XCTAssertTrue(ReceiptMatcher.isExact("Milk 2% Gal", "Milk"))
        XCTAssertTrue(ReceiptMatcher.isExact("Bnls Chkn Thigh", "Chicken thighs"))
        XCTAssertTrue(ReceiptMatcher.isExact("Large Eggs 12 Ct", "Eggs"))
        XCTAssertFalse(ReceiptMatcher.isExact("Peanut Butter", "Butter"))
        XCTAssertFalse(ReceiptMatcher.isExact("Almond Milk", "Milk"))
        XCTAssertFalse(ReceiptMatcher.isExact("Sharp Cheddar", "Cheddar"))
    }
}

final class AvoidListTests: XCTestCase {
    func testAllergenTagsAndIngredientText() {
        XCTAssertEqual(AvoidList.warnings(allergens: ["en:peanuts", "en:soybeans"], ingredients: nil, avoid: ["peanut", "gluten"]), ["Peanut"])
        XCTAssertEqual(AvoidList.warnings(allergens: [], ingredients: "Water, wheat flour, GLUTEN, salt", avoid: ["Gluten", "milk"]), ["Gluten"])
        XCTAssertEqual(AvoidList.warnings(allergens: ["en:milk"], ingredients: nil, avoid: ["milk"]), ["Milk"])
    }

    func testVeryShortWordsAreIgnoredAndMessages() {
        XCTAssertTrue(AvoidList.warnings(allergens: ["en:nuts"], ingredients: nil, avoid: ["ab"]).isEmpty)
        XCTAssertEqual(AvoidList.message(["Peanut", "Milk"]), "Contains peanut, milk")
        XCTAssertNil(AvoidList.message([]))
    }
}

final class RouteLearningTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func trip(_ n: Int, _ aisles: [Aisle]) -> [RouteEvent] {
        aisles.enumerated().map { RouteEvent(aisle: $0.element, date: t0 + Double(n) * 86_400 + Double($0.offset) * 300) }
    }

    func testNeedsThreeTrips() {
        let two = trip(0, [.bakery, .produce]) + trip(1, [.bakery, .produce])
        XCTAssertNil(RouteLearning.order(current: Aisle.allCases, events: two))
        XCTAssertEqual(RouteLearning.trips(from: two).count, 2)
        XCTAssertTrue(RouteLearning.trips(from: trip(0, [.produce])).isEmpty)
    }

    func testLearnsTheWalkingOrderAndKeepsUnseenAisles() throws {
        let events = trip(0, [.bakery, .produce, .dairy, .meat]) + trip(1, [.bakery, .produce, .dairy, .meat]) + trip(2, [.bakery, .produce, .dairy])
        let learned = try XCTUnwrap(RouteLearning.order(current: Aisle.allCases, events: events))
        XCTAssertEqual(Array(learned.prefix(4)), [.bakery, .produce, .dairy, .meat])
        XCTAssertEqual(Set(learned), Set(Aisle.allCases))
        XCTAssertEqual(Array(learned.suffix(5)), [.pantry, .frozen, .drinks, .household, .other])
        XCTAssertNil(RouteLearning.order(current: learned, events: events))
    }

    func testMajorityWinsAndUnseenAisleStaysPut() {
        let mixed = trip(0, [.produce, .dairy]) + trip(1, [.produce, .dairy]) + trip(2, [.dairy, .produce])
        XCTAssertEqual(Array(RouteLearning.order(current: [.dairy, .produce, .bakery], events: mixed)!.prefix(2)), [.produce, .dairy])
        let gap = trip(0, [.frozen, .bakery]) + trip(1, [.frozen, .bakery]) + trip(2, [.frozen, .bakery])
        XCTAssertEqual(RouteLearning.order(current: [.bakery, .produce, .frozen], events: gap), [.frozen, .produce, .bakery])
    }
}

final class ShelfLifeTests: XCTestCase {
    func testKnownFoods() {
        XCTAssertEqual(ShelfLife.days(for: "Baby spinach", aisle: .produce), 5)
        XCTAssertEqual(ShelfLife.days(for: "Chicken thighs", aisle: .meat), 2)
        XCTAssertEqual(ShelfLife.days(for: "Eggs", aisle: .dairy), 28)
        XCTAssertEqual(ShelfLife.days(for: "Almond milk", aisle: .dairy), 7)
        XCTAssertEqual(ShelfLife.days(for: "Mystery produce", aisle: .produce), 7)
    }

    func testNonPerishablesAreNotTracked() {
        XCTAssertNil(ShelfLife.days(for: "Canned beans", aisle: .pantry))
        XCTAssertNil(ShelfLife.days(for: "Dish soap", aisle: .household))
    }
}

final class NearbyStoreTests: XCTestCase {
    private func shop(_ name: String, _ lat: Double, _ lon: Double) -> Shop {
        var shop = Shop(name: name)
        shop.latitude = lat
        shop.longitude = lon
        return shop
    }

    override func tearDown() {
        NearbyStore.record(nil)
        super.tearDown()
    }

    func testNearestWithinRadius() {
        let kroger = shop("Kroger", 39.1000, -84.5000), walmart = shop("Walmart", 39.1100, -84.5000)
        XCTAssertEqual(NearbyStore.nearest(to: 39.1002, -84.5001, among: [kroger, walmart])?.name, "Kroger")
        XCTAssertNil(NearbyStore.nearest(to: 39.1050, -84.5000, among: [kroger, walmart]))
        XCTAssertEqual(NearbyStore.nearest(to: 39.1098, -84.5000, among: [kroger, walmart])?.name, "Walmart")
    }

    func testRecordedStoreExpiresAndRespectsDeletion() {
        let kroger = shop("Kroger", 39.1, -84.5), walmart = shop("Walmart", 39.11, -84.5)
        NearbyStore.record(kroger.id)
        XCTAssertEqual(NearbyStore.currentShopID(among: [kroger, walmart]), kroger.id)
        XCTAssertNil(NearbyStore.currentShopID(among: [kroger, walmart], now: Date().addingTimeInterval(4 * 3600)))
        XCTAssertNil(NearbyStore.currentShopID(among: [walmart]))
        NearbyStore.record(nil)
        XCTAssertNil(NearbyStore.currentShopID(among: [kroger, walmart]))
    }
}
