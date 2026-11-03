import Foundation

/// Where you are in a shopping trip: how much is in the cart, and which aisle to head to next.
struct ShoppingProgress: Equatable {
    var inCart: Int
    var total: Int
    /// The first aisle, in walking order, that still has something to get.
    var nextAisle: Aisle?
    /// That aisle's label in the store, like "Aisle 9", if you've given it one.
    var nextLabel: String?
    /// How many things are left in that aisle.
    var leftInNextAisle: Int

    var remaining: Int { total - inCart }
    var isDone: Bool { total > 0 && inCart == total }
    var fraction: Double { total == 0 ? 0 : Double(inCart) / Double(total) }

    init(items: [GroceryItem], order: [Aisle], label: (Aisle) -> String? = { _ in nil }) {
        total = items.count
        inCart = items.filter(\.isChecked).count
        let needed = items.filter { !$0.isChecked }
        let next = order.first { aisle in needed.contains { $0.aisle == aisle } }
            ?? needed.first?.aisle
        nextAisle = next
        nextLabel = next.flatMap(label)
        leftInNextAisle = next.map { aisle in needed.filter { $0.aisle == aisle }.count } ?? 0
    }

    /// "Next: Dairy & Eggs, Aisle 9 · 2 items", or nil when nothing is left.
    var nextText: String? {
        guard let nextAisle else { return nil }
        var text = "Next: \(nextAisle.rawValue)"
        if let nextLabel { text += ", \(nextLabel)" }
        return text + " · \(leftInNextAisle) item\(leftInNextAisle == 1 ? "" : "s")"
    }
}
