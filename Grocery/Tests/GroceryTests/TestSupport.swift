import XCTest

/// A fresh, empty store and clean preferences for every test, so tests never see each other's data.
class StoreTestCase: XCTestCase {
    var store: GroceryStore!

    override func setUp() {
        super.setUp()
        for key in ["tracksStock", "monthlyBudget", "avoidWords", "expiryReminders", "nearbyShopID", "nearbyShopDate"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Start every test from no saved files at all.
        for name in Storage.fileNames {
            try? FileManager.default.removeItem(at: Storage.url(name))
        }
        try? FileManager.default.removeItem(at: Storage.directory.appending(path: "Recovered"))
        store = GroceryStore()
        store.items = []
        store.shops = []
        store.favorites = []
        store.meals = []
        store.history = []
        store.recurring = []
        store.plan = []
        store.stock = []
        store.spending = []
    }

    func savedData(_ name: String) -> Data? {
        try? Data(contentsOf: Storage.url(name))
    }

    func modificationDate(_ name: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Storage.url(name).path))?[.modificationDate] as? Date
    }

    func decodedItems() -> [GroceryItem] {
        savedData("grocery").flatMap { try? JSONDecoder().decode([GroceryItem].self, from: $0) } ?? []
    }

    func day(_ offset: Int, from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }
}
