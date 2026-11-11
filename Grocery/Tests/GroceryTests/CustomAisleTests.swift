import XCTest

final class CustomAisleTests: StoreTestCase {
    func testAddingTrimsAndRejectsDuplicatesAndCategoryNames() {
        XCTAssertNotNil(store.addCustomAisle(named: "  Aisle 5 "))
        XCTAssertEqual(store.customAisles.map(\.name), ["Aisle 5"])
        XCTAssertNil(store.addCustomAisle(named: "aisle 5"))
        XCTAssertNil(store.addCustomAisle(named: "Produce"))
        XCTAssertNil(store.addCustomAisle(named: "   "))
    }

    func testAnItemInACustomAisleLeavesItsCategorySection() throws {
        let baking = try XCTUnwrap(store.addCustomAisle(named: "Baking"))
        store.add(name: "Flour", quantity: 1, aisle: .pantry, customAisleID: baking.id)
        store.add(name: "Rice", quantity: 1, aisle: .pantry)
        let groups = store.sectionGroups(store.items, shop: nil)
        XCTAssertEqual(groups.map(\.section), [.aisle(.pantry), .custom(baking.id)])
        XCTAssertEqual(groups[0].items.map(\.name), ["Rice"])
        XCTAssertEqual(groups[1].items.map(\.name), ["Flour"])
    }

    func testCustomAislesDefaultToJustBeforeOther() throws {
        let baking = try XCTUnwrap(store.addCustomAisle(named: "Baking"))
        let sections = Shop(name: "Test").orderedSections(custom: [baking])
        XCTAssertEqual(sections.last, .aisle(.other))
        XCTAssertEqual(sections[sections.count - 2], .custom(baking.id))
    }

    func testDraggingASectionRemembersWhereItWent() throws {
        let baking = CustomAisle(name: "Baking")
        var shop = Shop(name: "Test")
        var sections = shop.orderedSections(custom: [baking])
        let from = try XCTUnwrap(sections.firstIndex(of: .custom(baking.id)))
        let to = try XCTUnwrap(sections.firstIndex(of: .aisle(.dairy)))
        let moved = sections.remove(at: from)
        sections.insert(moved, at: to + 1)
        shop.setSectionOrder(sections)
        XCTAssertEqual(shop.orderedSections(custom: [baking]), sections)
        let index = try XCTUnwrap(shop.orderedSections(custom: [baking]).firstIndex(of: .custom(baking.id)))
        XCTAssertEqual(shop.orderedSections(custom: [baking])[index - 1], .aisle(.dairy))
    }

    func testAnAisleDraggedToTheTopComesFirst() {
        let a = CustomAisle(name: "A"), b = CustomAisle(name: "B")
        var shop = Shop(name: "Test")
        var sections = shop.orderedSections(custom: [a, b])
        sections.removeAll { $0 == .custom(a.id) || $0 == .custom(b.id) }
        sections.insert(contentsOf: [.custom(a.id), .custom(b.id)], at: 0)
        shop.setSectionOrder(sections)
        XCTAssertEqual(Array(shop.orderedSections(custom: [a, b]).prefix(2)), [.custom(a.id), .custom(b.id)])
    }

    func testDeletingPutsItemsBackUnderTheirCategory() throws {
        let baking = try XCTUnwrap(store.addCustomAisle(named: "Baking"))
        store.add(name: "Flour", quantity: 1, aisle: .pantry, customAisleID: baking.id)
        store.deleteCustomAisle(baking.id)
        XCTAssertTrue(store.customAisles.isEmpty)
        XCTAssertNil(store.items[0].customAisleID)
        XCTAssertEqual(store.sectionGroups(store.items, shop: nil).map(\.section), [.aisle(.pantry)])
    }

    func testAnUnknownAisleIdFallsBackToTheCategory() {
        store.add(name: "Flour", quantity: 1, aisle: .pantry, customAisleID: UUID())
        XCTAssertNil(store.items[0].customAisleID)
    }

    func testBackupKeepsCustomAisles() throws {
        _ = store.addCustomAisle(named: "Baking")
        let backup = store.makeBackup()
        store.customAisles = []
        store.restore(backup)
        XCTAssertEqual(store.customAisles.map(\.name), ["Baking"])
    }

    func testOldStoresWithoutAnchorsStillDecode() throws {
        let shop = Shop(name: "Old")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shop)) as? [String: Any])
        json.removeValue(forKey: "customAnchors")
        let decoded = try JSONDecoder().decode(Shop.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.customAnchors)
    }
}
