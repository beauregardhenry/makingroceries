import Foundation

extension GroceryStore {
    /// The lists as the watch shows them: one group per store with something on it, then "Any Store".
    func watchSnapshot() -> WatchSnapshot {
        func entries(_ items: [GroceryItem], order: [Aisle]) -> [WatchSnapshot.Entry] {
            items.sorted { (order.firstIndex(of: $0.aisle) ?? 0) < (order.firstIndex(of: $1.aisle) ?? 0) }
                .prefix(WatchSnapshot.maxItemsPerGroup)
                .map { .init(id: $0.id.uuidString, name: $0.name, quantity: $0.quantity, note: $0.note, isChecked: $0.isChecked) }
        }
        var groups: [WatchSnapshot.Group] = []
        for shop in shops {
            let mine = items.filter { $0.shopID == shop.id }
            if !mine.isEmpty { groups.append(.init(id: shop.id.uuidString, name: shop.name, items: entries(mine, order: shop.orderedAisles))) }
        }
        let loose = items.filter { $0.shopID == nil }
        if !loose.isEmpty { groups.append(.init(id: "any", name: "Any Store", items: entries(loose, order: Aisle.allCases))) }
        return WatchSnapshot(groups: groups)
    }
}
