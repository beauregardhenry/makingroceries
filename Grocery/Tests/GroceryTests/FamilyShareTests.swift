import XCTest

final class FamilyShareTests: StoreTestCase {
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// Joins the family's copy of one file the way FamilySync does the first time: line up ids, then combine.
    private func join<T: Encodable>(_ name: String, _ theirs: T) throws {
        let data = try encoded(theirs)
        store.adoptFamilyIDs(name: name, remote: data)
        XCTAssertNotNil(store.applyCloudCopy(name: name, remote: data, base: nil))
    }

    func testOnlyTheListAndWhatItNeedsAreShared() {
        XCTAssertEqual(GroceryStore.familyFileNames, ["shops", "customAisles", "people", "registryPeople", "grocery"])
        XCTAssertTrue(Set(GroceryStore.familyFileNames).isSubset(of: GroceryStore.cloudFileNames))
        for privateFile in ["meals", "history", "spending", "goals", "stock"] {
            XCTAssertFalse(GroceryStore.familyFileNames.contains(privateFile))
        }
    }

    func testJoiningDoesNotListTheSameStoreOrItemTwice() throws {
        let mine = Shop(name: "Kroger")
        store.shops = [mine]
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: mine.id)
        store.add(name: "Eggs", quantity: 1, aisle: .dairy, shopID: mine.id)

        let family = Shop(name: " kroger ")
        let other = Shop(name: "Costco")
        var milk = GroceryItem(name: "milk", aisle: .dairy, shopID: family.id)
        milk.quantity = 2
        let bread = GroceryItem(name: "Bread", aisle: .bakery, shopID: other.id)

        try join("shops", [family, other])
        try join("grocery", [milk, bread])

        XCTAssertEqual(store.shops.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [family.id, other.id].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.filter { $0.name.lowercased() == "milk" }.count, 1)
        XCTAssertTrue(store.items.allSatisfy { $0.shopID == family.id || $0.shopID == other.id })
        XCTAssertEqual(store.items.first { $0.name == "Eggs" }?.shopID, family.id)
    }

    func testAStoreTakesTheFamilyIdEverywhereItIsUsed() throws {
        let mine = Shop(name: "Aldi")
        store.shops = [mine]
        store.history = [PastItem(name: "Rice", aisle: .pantry, shopID: mine.id,
                                  priceHistory: [PricePoint(shopID: mine.id, price: 2, date: Date())])]
        store.recurring = [RecurringItem(name: "Rice", shopID: mine.id, everyDays: 7, nextDue: Date())]
        store.spending = [SpendRecord(date: Date(), shopID: mine.id, amount: 20)]

        let family = Shop(name: "ALDI")
        store.adoptFamilyIDs(name: "shops", remote: try encoded([family]))

        XCTAssertEqual(store.shops.map(\.id), [family.id])
        XCTAssertEqual(store.history[0].shopID, family.id)
        XCTAssertEqual(store.history[0].priceHistory?[0].shopID, family.id)
        XCTAssertEqual(store.recurring[0].shopID, family.id)
        XCTAssertEqual(store.spending[0].shopID, family.id)
    }

    func testCustomAislesFollowIntoItemsAndStoreOrder() throws {
        let mine = try XCTUnwrap(store.addCustomAisle(named: "Baking"))
        var shop = Shop(name: "Test")
        shop.customAnchors = [mine.id.uuidString: Aisle.dairy.rawValue]
        store.shops = [shop]
        store.add(name: "Flour", quantity: 1, aisle: .pantry, customAisleID: mine.id)

        let family = CustomAisle(name: "baking")
        store.adoptFamilyIDs(name: "customAisles", remote: try encoded([family]))

        XCTAssertEqual(store.customAisles.map(\.id), [family.id])
        XCTAssertEqual(store.items[0].customAisleID, family.id)
        XCTAssertEqual(store.shops[0].customAnchors, [family.id.uuidString: Aisle.dairy.rawValue])
    }

    func testPeopleFollowIntoClothingAndGifts() throws {
        let kid = Person(name: "Sam")
        let grandma = RegistryPerson(name: "Grandma")
        store.people = [kid]
        store.registryPeople = [grandma]
        var shirt = GroceryItem(name: "Shirt")
        shirt.personID = kid.id
        var scarf = GroceryItem(name: "Scarf")
        scarf.giftForID = grandma.id
        store.items = [shirt, scarf]

        let familyKid = Person(name: "sam")
        let familyGrandma = RegistryPerson(name: "Grandma ")
        store.adoptFamilyIDs(name: "people", remote: try encoded([familyKid]))
        store.adoptFamilyIDs(name: "registryPeople", remote: try encoded([familyGrandma]))

        XCTAssertEqual(store.people.map(\.id), [familyKid.id])
        XCTAssertEqual(store.registryPeople.map(\.id), [familyGrandma.id])
        XCTAssertEqual(store.items[0].personID, familyKid.id)
        XCTAssertEqual(store.items[1].giftForID, familyGrandma.id)
    }

    func testBoughtItemsAndDifferentStoresStaySeparate() throws {
        let a = Shop(name: "A"), b = Shop(name: "B")
        store.shops = [a, b]
        store.add(name: "Milk", quantity: 1, aisle: .dairy, shopID: a.id)
        let mineID = store.items[0].id

        var bought = GroceryItem(name: "Milk", aisle: .dairy, shopID: a.id)
        bought.isChecked = true
        let elsewhere = GroceryItem(name: "Milk", aisle: .dairy, shopID: b.id)
        store.adoptFamilyIDs(name: "grocery", remote: try encoded([bought, elsewhere]))

        XCTAssertEqual(store.items[0].id, mineID)
    }

    func testEntriesTheFamilyDoesNotHaveKeepTheirIds() throws {
        let match = Shop(name: "Kroger"), mineOnly = Shop(name: "Corner Shop")
        let baking = try XCTUnwrap(store.addCustomAisle(named: "Baking"))
        let bulk = try XCTUnwrap(store.addCustomAisle(named: "Bulk"))
        var shop = match
        shop.customAnchors = [baking.id.uuidString: "", bulk.id.uuidString: Aisle.dairy.rawValue]
        store.shops = [shop, mineOnly]
        let sam = Person(name: "Sam"), alex = Person(name: "Alex")
        let grandma = RegistryPerson(name: "Grandma"), uncle = RegistryPerson(name: "Uncle Joe")
        store.people = [sam, alex]
        store.registryPeople = [grandma, uncle]
        var shirt = GroceryItem(name: "Shirt"); shirt.personID = alex.id
        var tie = GroceryItem(name: "Tie"); tie.giftForID = uncle.id
        var flour = GroceryItem(name: "Flour", shopID: mineOnly.id); flour.customAisleID = bulk.id
        let soap = GroceryItem(name: "Soap")
        store.items = [shirt, tie, flour, soap]
        store.history = [PastItem(name: "Soap", aisle: .other, priceHistory: [PricePoint(shopID: nil, price: 1, date: Date())])]
        store.recurring = [RecurringItem(name: "Soap", everyDays: 7, nextDue: Date())]
        store.spending = [SpendRecord(date: Date(), shopID: mineOnly.id, amount: 5)]

        let familySoap = GroceryItem(name: "Soap")
        store.adoptFamilyIDs(name: "shops", remote: try encoded([Shop(name: "kroger")]))
        store.adoptFamilyIDs(name: "customAisles", remote: try encoded([CustomAisle(name: "baking")]))
        store.adoptFamilyIDs(name: "people", remote: try encoded([Person(name: "Sam")]))
        store.adoptFamilyIDs(name: "registryPeople", remote: try encoded([RegistryPerson(name: "Grandma")]))
        store.adoptFamilyIDs(name: "grocery", remote: try encoded([familySoap]))

        XCTAssertEqual(store.shops[1].id, mineOnly.id)
        XCTAssertEqual(store.customAisles[1].id, bulk.id)
        XCTAssertEqual(store.shops[0].customAnchors?[bulk.id.uuidString], Aisle.dairy.rawValue)
        XCTAssertEqual(store.people[1].id, alex.id)
        XCTAssertEqual(store.registryPeople[1].id, uncle.id)
        XCTAssertEqual(store.items[0].personID, alex.id)
        XCTAssertEqual(store.items[1].giftForID, uncle.id)
        XCTAssertEqual(store.items[2].shopID, mineOnly.id)
        XCTAssertEqual(store.items[2].customAisleID, bulk.id)
        XCTAssertEqual(store.items[3].id, familySoap.id)
        XCTAssertEqual(store.spending[0].shopID, mineOnly.id)
        XCTAssertNil(store.history[0].shopID)
    }

    func testEachFamilyEntryIsMatchedOnlyOnce() {
        let ours = [CustomAisle(name: "Bulk"), CustomAisle(name: "Bulk")]
        let theirs = [CustomAisle(name: "Bulk")]
        let map = GroceryStore.matchingIDs(ours: ours, theirs: theirs) { $0.name }
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[ours[0].id], theirs[0].id)
    }

    func testEntriesAlreadySharedAndUnreadableCopiesChangeNothing() throws {
        let shop = Shop(name: "Kroger")
        store.shops = [shop]
        store.adoptFamilyIDs(name: "shops", remote: try encoded([shop, Shop(name: "Kroger")]))
        XCTAssertEqual(store.shops.map(\.id), [shop.id])

        store.adoptFamilyIDs(name: "shops", remote: Data("not json".utf8))
        store.adoptFamilyIDs(name: "meals", remote: try encoded([shop]))
        XCTAssertEqual(store.shops.map(\.id), [shop.id])
    }
}
