import Foundation

/// Something you bought that's now in your kitchen, with a rough use-by date.
struct StockEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var aisle: Aisle
    var bought: Date
    var expires: Date
}

enum ShelfLife {
    /// Rough days an item keeps, by what it is. Nil means not worth tracking (cans, cleaning supplies).
    /// These are guides, not food-safety advice.
    static func days(for name: String, aisle: Aisle) -> Int? {
        let n = name.lowercased()
        let words = Set(n.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ list: [String]) -> Bool { list.contains { n.contains($0) } }

        if has(["spinach", "lettuce", "greens", "arugula", "kale", "herb", "cilantro", "parsley", "basil", "mushroom"]) { return 5 }
        if has(["berries", "strawberr", "raspberr", "blueberr", "grapes"]) { return 6 }
        if has(["banana", "avocado", "tomato", "peach", "pear", "mango"]) { return 5 }
        if has(["apple", "orange", "lemon", "lime", "grapefruit", "carrot", "celery", "cabbage"]) { return 14 }
        if has(["potato", "onion", "garlic", "squash"]) { return 30 }
        if has(["chicken", "turkey", "ground", "fish", "salmon", "shrimp", "seafood", "steak", "pork", "beef"]) { return 2 }
        if has(["bacon", "ham", "deli", "sausage", "hot dog"]) { return 7 }
        if words.contains("milk") || has(["cream", "half and half"]) { return 7 }
        if has(["yogurt", "yoghurt", "cottage", "tofu"]) { return 12 }
        if has(["cheese", "cheddar", "mozzarella", "parmesan", "butter"]) { return 28 }
        if words.contains("eggs") || words.contains("egg") { return 28 }
        if has(["bread", "bagel", "tortilla", "bun", "roll", "croissant", "muffin", "sourdough"]) { return 6 }
        switch aisle {
        case .produce: return 7
        case .dairy: return 10
        case .meat: return 3
        case .bakery: return 5
        default: return nil
        }
    }
}

extension GroceryStore {
    /// Whether checking something off also adds it to "at home". On unless you turn it off.
    static var tracksStock: Bool {
        get { UserDefaults.standard.object(forKey: "tracksStock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tracksStock") }
    }

    func recordStock(of item: GroceryItem, now: Date = Date()) {
        guard Self.tracksStock, let days = ShelfLife.days(for: item.name, aisle: item.aisle),
              let expires = Calendar.current.date(byAdding: .day, value: days, to: now) else { return }
        stock.removeAll { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }
        stock.append(StockEntry(name: item.name, aisle: item.aisle, bought: now, expires: expires))
    }

    /// Everything at home, soonest use-by first.
    func stockByExpiry() -> [StockEntry] {
        stock.sorted { $0.expires < $1.expires }
    }

    /// Items to use by the end of the day `days` days from now (or already past).
    func usingSoon(within days: Int = 2, now: Date = Date()) -> [StockEntry] {
        let limit = Calendar.current.date(byAdding: .day, value: days + 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return stockByExpiry().filter { $0.expires < limit }
    }

    func removeStock(_ id: UUID) {
        stock.removeAll { $0.id == id }
    }

    /// Used up, so it can go back on the list.
    func useUp(_ entry: StockEntry, addBack: Bool) {
        removeStock(entry.id)
        if addBack { addOrBump(name: entry.name, aisle: entry.aisle, shopID: nil, inferShop: true) }
    }
}
