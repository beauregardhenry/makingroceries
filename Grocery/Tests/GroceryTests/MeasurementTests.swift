import XCTest

@MainActor
final class MeasurementTests: StoreTestCase {
    private var emma: Person!

    override func setUp() async throws {
        try await super.setUp()
        emma = store.addPerson(named: "Emma")
    }

    func testMeasurementsAreAddedOnceAndInTitleCase() throws {
        XCTAssertEqual(store.addMeasurement("shoes", for: emma.id)?.label, "Shoes")
        XCTAssertNil(store.addMeasurement("Shoe", for: emma.id))
        XCTAssertNil(store.addMeasurement("  ", for: emma.id))
        XCTAssertNil(store.addMeasurement("Hat", for: UUID()))
        XCTAssertEqual(store.people[0].measurements?.map(\.label), ["Shoes"])
    }

    func testSettingAValueNotesTheDate() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let later = start.addingTimeInterval(86_400 * 90)
        let shoes = try XCTUnwrap(store.addMeasurement("Shoes", for: emma.id, on: start))
        store.setMeasurement(shoes.id, to: "7", for: emma.id, on: later)
        XCTAssertEqual(store.people[0].measurements?[0].value, "7")
        XCTAssertEqual(store.people[0].measurements?[0].updated, later)
        store.setMeasurement(shoes.id, to: "7", for: emma.id, on: start)
        XCTAssertEqual(store.people[0].measurements?[0].updated, later, "an unchanged value keeps its date")
    }

    func testRemovingTheLastMeasurementClearsTheList() throws {
        let hat = try XCTUnwrap(store.addMeasurement("Hat", for: emma.id))
        store.removeMeasurement(hat.id, for: emma.id)
        XCTAssertNil(store.people[0].measurements)
        store.removeMeasurement(hat.id, for: UUID())
    }

    func testASavedSizeIsSuggestedForMatchingClothing() throws {
        let shoes = try XCTUnwrap(store.addMeasurement("Shoes", for: emma.id))
        let pants = try XCTUnwrap(store.addMeasurement("Pants", for: emma.id))
        _ = store.addMeasurement("Shirt", for: emma.id)
        store.setMeasurement(shoes.id, to: "7", for: emma.id)
        store.setMeasurement(pants.id, to: "10 Kids", for: emma.id)

        XCTAssertEqual(store.suggestedSize(for: emma.id, itemNamed: "Running Shoes"), "7")
        XCTAssertEqual(store.suggestedSize(for: emma.id, itemNamed: "Sneakers"), "7")
        XCTAssertEqual(store.suggestedSize(for: emma.id, itemNamed: "jeans"), "10 Kids")
        XCTAssertNil(store.suggestedSize(for: emma.id, itemNamed: "T-Shirt"), "an empty Shirt size suggests nothing")
        XCTAssertNil(store.suggestedSize(for: emma.id, itemNamed: "Scarf"))
        XCTAssertNil(store.suggestedSize(for: nil, itemNamed: "Shoes"))
    }

    func testTheLastSizeBoughtWinsOverTheSavedOne() throws {
        let shoes = try XCTUnwrap(store.addMeasurement("Shoes", for: emma.id))
        store.setMeasurement(shoes.id, to: "7", for: emma.id)
        store.rememberSize("7.5", for: emma.id, itemNamed: "Shoes")
        XCTAssertEqual(store.suggestedSize(for: emma.id, itemNamed: "Shoes"), "7.5")
    }

    func testOldPeopleWithoutMeasurementsStillDecode() throws {
        let data = Data(#"[{"id":"6C45C1E5-4251-4CEC-A047-8E222B2C889C","name":"Jake"}]"#.utf8)
        let people = try JSONDecoder().decode([Person].self, from: data)
        XCTAssertNil(people[0].measurements)
        XCTAssertEqual(MeasurementLabels.common.first, "Shirt")
    }
}
