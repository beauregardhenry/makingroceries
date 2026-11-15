import XCTest

@MainActor
final class NameColorTests: StoreTestCase {
    func testAPickedColorIsTheSameOnBothLists() throws {
        let emma = try XCTUnwrap(store.addPerson(named: "Emma"))
        let giftEmma = try XCTUnwrap(store.addRegistryPerson(named: "emma"))
        store.setColor(.mint, ofPerson: emma.id)
        XCTAssertEqual(store.color(ofPerson: emma.id), .mint)
        XCTAssertEqual(store.color(ofRegistryPerson: giftEmma.id), .mint, "Emma is mint everywhere")
        store.setColor(.red, ofRegistryPerson: giftEmma.id)
        XCTAssertEqual(store.color(ofPerson: emma.id), .red, "and changing it on Registry changes it on Clothing")
        XCTAssertEqual(store.people[0].color, "red")
    }

    func testANameStartsWithTheSameColorEverywhere() throws {
        let jake = try XCTUnwrap(store.addPerson(named: "Jake"))
        _ = store.addPerson(named: "Mom")
        let giftJake = try XCTUnwrap(store.addRegistryPerson(named: "Jake"))
        XCTAssertEqual(store.color(ofPerson: jake.id), store.color(ofRegistryPerson: giftJake.id))
        XCTAssertEqual(NameColor.resolved(nil, name: " jake "), NameColor.resolved(nil, name: "Jake"))
    }

    func testAColorPickedOnOneListIsUsedForTheOtherEvenIfOnlyOneHasIt() throws {
        let grandma = try XCTUnwrap(store.addRegistryPerson(named: "Grandma"))
        store.setColor(.brown, ofRegistryPerson: grandma.id)
        let family = try XCTUnwrap(store.addPerson(named: "Grandma"))
        XCTAssertEqual(store.color(ofPerson: family.id), .brown, "someone added later takes the color already picked")
        store.setColor(.red, ofRegistryPerson: UUID())
        store.setColor(.red, ofPerson: UUID())
        XCTAssertEqual(store.color(ofRegistryPerson: grandma.id), .brown)
    }

    func testUnknownColorsFallBack() {
        XCTAssertEqual(NameColor.resolved("plaid", name: "Sam"), NameColor.resolved(nil, name: "Sam"))
        XCTAssertEqual(NameColor.resolved("teal", name: "Sam"), .teal)
        XCTAssertEqual(NameColor.allCases.map(\.title).first, "Blue")
        XCTAssertEqual(NameColor.mint.id, "mint")
        XCTAssertEqual(NameColor.allCases.filter(\.prefersDarkText), [.yellow, .mint, .cyan])
    }
}
