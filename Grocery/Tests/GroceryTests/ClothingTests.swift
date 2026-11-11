import XCTest

final class ClothingTests: StoreTestCase {
    private func person(_ name: String) throws -> Person {
        try XCTUnwrap(store.addPerson(named: name))
    }

    func testPeopleAreAddedInOrderWithoutBlanksOrDuplicates() throws {
        _ = try person("Mom")
        _ = try person(" Emma ")
        XCTAssertNil(store.addPerson(named: "mom"))
        XCTAssertNil(store.addPerson(named: "   "))
        XCTAssertEqual(store.people.map(\.name), ["Mom", "Emma"])
    }

    func testClothingGetsItsOwnAisleSizeAndDates() throws {
        let emma = try person("Emma")
        store.add(name: "Jeans", quantity: 1, aisle: .produce, list: .clothing, personID: emma.id, clothingSize: " 10 Kids ")
        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.list, .clothing)
        XCTAssertEqual(item.aisle, .clothing)
        XCTAssertEqual(item.clothingSize, "10 Kids")
        XCTAssertNotNil(item.sizeDate)
        XCTAssertNotNil(item.addedAt)
        XCTAssertEqual(item.personID, emma.id)
    }

    func testClothingStaysOffEveryOtherList() {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        store.add(name: "T-shirt", quantity: 1, aisle: .clothing, list: .clothing)
        store.add(name: "Sunscreen", quantity: 1, aisle: .pharmacy, list: .travel)
        XCTAssertEqual(store.widgetItems(shopID: nil).map(\.name), ["Milk"])
        XCTAssertEqual(store.watchSnapshot().groups.flatMap(\.items).map(\.name), ["Milk"])
        XCTAssertEqual(store.items.filter { !$0.isSeparate }.map(\.name), ["Milk"])
        XCTAssertEqual(store.items.filter { $0.list == .clothing }.map(\.name), ["T-shirt"])
    }

    func testClothingDoesNotMergeIntoTheSameNamedGroceryItem() {
        store.addOrBump(name: "Socks", shopID: nil)
        store.addOrBump(name: "Socks", shopID: nil, list: .clothing)
        store.addOrBump(name: "Socks", shopID: nil, list: .clothing)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first { $0.list == .clothing }?.quantity, 2)
        XCTAssertEqual(store.items.first { $0.list == .clothing }?.aisle, .clothing)
    }

    func testSectionsFollowTheFamilyOrderWithLooseItemsLast() throws {
        let mom = try person("Mom"), emma = try person("Emma")
        store.add(name: "Shoes", quantity: 1, aisle: .clothing, list: .clothing, personID: emma.id)
        store.add(name: "Hat", quantity: 1, aisle: .clothing, list: .clothing)
        store.add(name: "Scarf", quantity: 1, aisle: .clothing, list: .clothing, personID: mom.id)
        let sections = store.clothingSections(store.items)
        XCTAssertEqual(sections.map { $0.person?.name ?? "none" }, ["Mom", "Emma", "none"])
        XCTAssertEqual(sections[2].items.map(\.name), ["Hat"])
        store.people.reverse()
        XCTAssertEqual(store.clothingSections(store.items).map { $0.person?.name ?? "none" }, ["Emma", "Mom", "none"])
    }

    func testDeletingAPersonKeepsTheirClothing() throws {
        let emma = try person("Emma")
        store.add(name: "Shoes", quantity: 1, aisle: .clothing, list: .clothing, personID: emma.id)
        store.deletePerson(emma.id)
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items[0].personID)
        XCTAssertEqual(store.clothingSections(store.items).map { $0.person == nil }, [true])
    }

    func testAnItemWithADeletedPersonIDStillShowsUnderNoOneYet() {
        store.add(name: "Shoes", quantity: 1, aisle: .clothing, list: .clothing, personID: UUID())
        XCTAssertEqual(store.clothingSections(store.items).map { $0.person == nil }, [true])
    }

    func testChangingASizeNotesWhenAndBlankClearsIt() throws {
        let emma = try person("Emma")
        store.add(name: "Jeans", quantity: 1, aisle: .clothing, list: .clothing, personID: emma.id, clothingSize: "8")
        let id = store.items[0].id
        let later = Date().addingTimeInterval(86_400 * 3)
        store.setClothingSize("8", for: id, on: later)
        XCTAssertNotEqual(store.items[0].sizeDate, later, "the same size doesn't count as a change")
        store.setClothingSize("10", for: id, on: later)
        XCTAssertEqual(store.items[0].clothingSize, "10")
        XCTAssertEqual(store.items[0].sizeDate, later)
        store.setClothingSize("  ", for: id)
        XCTAssertNil(store.items[0].clothingSize)
        XCTAssertNil(store.items[0].sizeDate)
    }

    func testTheLastSizeIsRememberedPerPersonAndItem() throws {
        let emma = try person("Emma"), jake = try person("Jake")
        store.add(name: "Jeans", quantity: 1, aisle: .clothing, list: .clothing, personID: emma.id, clothingSize: "10")
        XCTAssertEqual(store.lastSize(for: emma.id, itemNamed: " jeans "), "10")
        XCTAssertNil(store.lastSize(for: jake.id, itemNamed: "Jeans"))
        XCTAssertNil(store.lastSize(for: emma.id, itemNamed: "Shoes"))
        XCTAssertNil(store.lastSize(for: nil, itemNamed: "Jeans"))
    }

    func testMovingClothingToAnotherPerson() throws {
        let mom = try person("Mom"), emma = try person("Emma")
        store.add(name: "Coat", quantity: 1, aisle: .clothing, list: .clothing, personID: mom.id)
        store.move(store.items[0], toPerson: emma.id)
        XCTAssertEqual(store.items[0].personID, emma.id)
    }

    func testTheMenuLinesShowTheDateAddedAndTheSize() {
        var item = GroceryItem(name: "Jeans")
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        item.addedAt = added
        item.clothingSize = "M"
        item.sizeDate = added
        let text: (Date) -> String = { "<\($0.timeIntervalSince1970)>" }
        XCTAssertEqual(ClothingInfo.lines(for: item, dateText: text), ["Added <1700000000.0>", "Size M"],
                       "a size set the same day it was added isn't repeated")
        item.sizeDate = added.addingTimeInterval(86_400 * 5)
        XCTAssertEqual(ClothingInfo.lines(for: item, dateText: text)[1], "Size M · set <1700432000.0>")
        item.clothingSize = nil
        XCTAssertEqual(ClothingInfo.lines(for: item, dateText: text)[1], "No size yet")
        XCTAssertEqual(ClothingInfo.lines(for: GroceryItem(name: "Old"), dateText: text), ["No size yet"],
                       "items from before dates were saved show no date")
    }

    func testPeopleAndClothingSurviveSavingBackupAndSync() throws {
        let emma = try person("Emma")
        store.add(name: "Jeans", quantity: 1, aisle: .clothing, list: .clothing, personID: emma.id, clothingSize: "10")
        XCTAssertEqual(GroceryStore().people.map(\.name), ["Emma"])
        XCTAssertEqual(GroceryStore().items.first?.clothingSize, "10")
        let backup = store.makeBackup()
        store.people = []
        store.restore(backup)
        XCTAssertEqual(store.people.map(\.name), ["Emma"])
        XCTAssertNotNil(store.cloudData(for: "people"))
        XCTAssertTrue(GroceryStore.cloudFileNames.contains("people"))
    }

    func testItemsAndBackupsSavedBeforeClothingStillLoad() throws {
        let old = #"{"id":"6E13AA21-DC89-43D4-8946-D42B12D97A25","name":"Milk","quantity":1,"aisle":"Dairy & Eggs","isChecked":false}"#
        let item = try JSONDecoder().decode(GroceryItem.self, from: Data(old.utf8))
        XCTAssertNotEqual(item.list, .clothing)
        XCTAssertFalse(item.isSeparate)
        XCTAssertNil(item.clothingSize)
        XCTAssertEqual(ShopFilter(raw: "clothing"), .list(.clothing))
    }
}
