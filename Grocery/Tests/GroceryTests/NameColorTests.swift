import XCTest

final class NameColorTests: StoreTestCase {
    func testPeopleGetColorsByPlaceUntilOneIsPicked() throws {
        let mom = try XCTUnwrap(store.addPerson(named: "Mom"))
        let jake = try XCTUnwrap(store.addPerson(named: "Jake"))
        XCTAssertEqual(store.color(ofPerson: mom.id), .blue)
        XCTAssertEqual(store.color(ofPerson: jake.id), .pink)
        store.setColor(.mint, ofPerson: jake.id)
        XCTAssertEqual(store.color(ofPerson: jake.id), .mint)
        XCTAssertEqual(store.people[1].color, "mint")
    }

    func testRegistryPeopleKeepTheirOwnColors() throws {
        let grandma = try XCTUnwrap(store.addRegistryPerson(named: "Grandma"))
        XCTAssertEqual(store.color(ofRegistryPerson: grandma.id), .blue)
        store.setColor(.brown, ofRegistryPerson: grandma.id)
        XCTAssertEqual(store.color(ofRegistryPerson: grandma.id), .brown)
        store.setColor(.red, ofRegistryPerson: UUID())
        store.setColor(.red, ofPerson: UUID())
        XCTAssertEqual(store.color(ofRegistryPerson: grandma.id), .brown)
    }

    func testDefaultsCycleAndUnknownColorsFallBack() {
        XCTAssertEqual(NameColor.resolved(nil, index: 8), .blue)
        XCTAssertEqual(NameColor.resolved("plaid", index: 1), .pink)
        XCTAssertEqual(NameColor.resolved("teal", index: 0), .teal)
        XCTAssertEqual(NameColor.allCases.map(\.title).first, "Blue")
        XCTAssertEqual(NameColor.mint.id, "mint")
    }
}
