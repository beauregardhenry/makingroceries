import XCTest

final class ListTableTests: StoreTestCase {
    func testEveryListHasAUniqueNameAndSyncs() {
        let names = GroceryStore.lists.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(Storage.fileNames, names)
        XCTAssertEqual(GroceryStore.cloudFileNames, names)
        for name in names {
            let data = store.cloudData(for: name)
            XCTAssertNotNil(data, "\(name) can be sent to the cloud")
            XCTAssertNotNil(store.applyCloudCopy(name: name, remote: data ?? Data(), base: nil), "\(name) merges a cloud copy")
        }
        XCTAssertNil(store.cloudData(for: "nope"))
        XCTAssertNil(store.applyCloudCopy(name: "nope", remote: Data(), base: nil))
    }

    func testEveryListIsSavedWhenItChanges() throws {
        store.favorites = [Favorite(name: "Milk", quantity: 1, aisle: .dairy)]
        store.people = [Person(name: "Emma")]
        store.customAisles = [CustomAisle(name: "Baking")]
        store.registryPeople = [RegistryPerson(name: "Gran")]
        for name in ["favorites", "people", "customAisles", "registryPeople"] {
            XCTAssertNotNil(savedData(name), "\(name) is written to its file")
        }
        let reopened = GroceryStore()
        XCTAssertEqual(reopened.customAisles.map(\.name), ["Baking"])
        XCTAssertEqual(reopened.registryPeople.map(\.name), ["Gran"])
        XCTAssertFalse(reopened.isFirstRun)
    }

    func testAFreshInstallIsAFirstRunWithSampleItems() {
        for name in Storage.fileNames { try? FileManager.default.removeItem(at: Storage.url(name)) }
        let fresh = GroceryStore()
        XCTAssertTrue(fresh.isFirstRun)
        XCTAssertFalse(fresh.items.isEmpty, "sample items")
        XCTAssertFalse(fresh.shops.isEmpty, "default stores")
    }
}
