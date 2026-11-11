import XCTest

final class RegistryTests: StoreTestCase {
    private func person(_ name: String) throws -> RegistryPerson {
        try XCTUnwrap(store.addRegistryPerson(named: name))
    }

    func testPeopleAreTrimmedAndNotDuplicated() throws {
        _ = try person("  Emma ")
        XCTAssertNil(store.addRegistryPerson(named: "emma"))
        XCTAssertNil(store.addRegistryPerson(named: " "))
        XCTAssertEqual(store.registryPeople.map(\.name), ["Emma"])
    }

    func testGiftsStayOffEveryOtherList() throws {
        let emma = try person("Emma")
        store.add(name: "Lego set", quantity: 1, aisle: .toys, list: .registry, giftForID: emma.id, occasion: "Birthday")
        let gift = store.items[0]
        XCTAssertEqual(gift.list, .registry)
        XCTAssertTrue(gift.isSeparate)
        XCTAssertEqual(gift.occasion, "Birthday")
        XCTAssertNil(gift.shopID)
        XCTAssertTrue(store.widgetItems(shopID: nil).isEmpty)
    }

    func testSectionsFollowTheListWithUnassignedLastAndBoughtAtTheBottom() throws {
        let emma = try person("Emma"), jake = try person("Jake")
        store.add(name: "Book", quantity: 1, aisle: .other, list: .registry, giftForID: jake.id)
        store.add(name: "Puzzle", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.add(name: "Bike", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.add(name: "Mystery", quantity: 1, aisle: .other, list: .registry)
        store.toggle(store.items[1])
        let groups = store.registrySections(store.items)
        XCTAssertEqual(groups.map { $0.person?.name }, ["Emma", "Jake", nil])
        XCTAssertEqual(groups[0].items.map(\.name), ["Bike", "Puzzle"])
    }

    func testBuyingMarksWhenAndKeepsItOutOfGroceryHistory() throws {
        let emma = try person("Emma")
        store.add(name: "Puzzle", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.toggle(store.items[0])
        XCTAssertTrue(store.items[0].isChecked)
        XCTAssertNotNil(store.items[0].boughtAt)
        XCTAssertNil(store.history.first { $0.name == "Puzzle" }?.purchases, "a gift is not a grocery purchase")
        store.toggle(store.items[0])
        XCTAssertNil(store.items[0].boughtAt)
    }

    func testDeletingAPersonKeepsTheirGifts() throws {
        let emma = try person("Emma")
        store.add(name: "Puzzle", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.deleteRegistryPerson(emma.id)
        XCTAssertNil(store.items[0].giftForID)
        XCTAssertEqual(store.registrySections(store.items).map { $0.person?.name }, [nil])
    }

    func testMovingAGiftToAnotherPerson() throws {
        let emma = try person("Emma"), jake = try person("Jake")
        store.add(name: "Puzzle", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.move(store.items[0], toGiftFor: jake.id)
        XCTAssertEqual(store.items[0].giftForID, jake.id)
    }

    func testMenuLines() {
        var item = GroceryItem(name: "Puzzle")
        item.addedAt = Date(timeIntervalSince1970: 0)
        item.occasion = "Birthday"
        XCTAssertEqual(RegistryInfo.lines(for: item, dateText: { _ in "Jan 1" }), ["Added Jan 1", "For Birthday"])
        item.isChecked = true
        XCTAssertEqual(RegistryInfo.lines(for: item, dateText: { _ in "Jan 1" }).last, "Bought")
        item.boughtAt = Date()
        XCTAssertEqual(RegistryInfo.lines(for: item, dateText: { _ in "Jan 2" }).last, "Bought Jan 2")
    }

    func testShareTextListsOnlyWhatIsStillNeeded() throws {
        let emma = try RegistryPerson(name: "Emma", birthday: Date(timeIntervalSince1970: 0))
        store.registryPeople = [emma]
        store.add(name: "Puzzle", quantity: 2, aisle: .other, list: .registry, giftForID: emma.id, occasion: "Birthday")
        store.add(name: "Bike", quantity: 1, aisle: .other, list: .registry, giftForID: emma.id)
        store.toggle(store.items[1])
        let text = RegistryInfo.shareText(gifts: store.items, sections: store.registrySections(store.items))
        XCTAssertTrue(text.hasPrefix("Gift list\n\nEmma (Birthday "))
        XCTAssertTrue(text.contains("☐ Puzzle ×2 (Birthday)"))
        XCTAssertFalse(text.contains("Bike"))
        XCTAssertEqual(RegistryInfo.shareText(gifts: [], sections: []), "Gift list\n\nNothing needed right now.")
    }

    func testBackupAndChipOrder() throws {
        _ = try person("Emma")
        let backup = store.makeBackup()
        store.registryPeople = []
        store.restore(backup)
        XCTAssertEqual(store.registryPeople.map(\.name), ["Emma"])
        let shop = Shop(name: "A")
        let entries = ChipOrder.entries(shops: [shop])
        XCTAssertEqual(entries, [.shop(shop.id), .list(.travel), .list(.clothing), .list(.registry)])
        XCTAssertEqual(ChipOrder.position(of: entries, list: .registry), -3)
        XCTAssertEqual(ShopFilter(raw: ShopFilter.list(.registry).raw), .list(.registry))
    }
}
