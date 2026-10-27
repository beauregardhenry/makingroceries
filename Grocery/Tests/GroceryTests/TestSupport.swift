import XCTest

/// A fresh, empty store and clean preferences for every test, so tests never see each other's data.
class StoreTestCase: XCTestCase {
    var store: GroceryStore!

    override func setUp() {
        super.setUp()
        for key in ["tracksStock", "monthlyBudget", "avoidWords", "expiryReminders", "nearbyShopID", "nearbyShopDate"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

    func day(_ offset: Int, from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }
}
