import Foundation

/// One thing to show in Spotlight search: a saved meal, something on the list, or something you've
/// bought before. Built here and handed to Core Spotlight by the app.
struct SpotlightEntry: Equatable, Identifiable {
    enum Kind: String { case meal, item, past }

    var kind: Kind
    /// The thing's own id, or its name for past items.
    var key: String
    var title: String
    var detail: String
    var keywords: [String]

    /// The searchable item's id, which says what to open when it's tapped.
    var id: String { "\(kind.rawValue):\(key)" }

    /// The kind and key from a tapped item's id.
    static func parse(_ id: String) -> (kind: Kind, key: String)? {
        guard let colon = id.firstIndex(of: ":"), let kind = Kind(rawValue: String(id[..<colon])) else { return nil }
        let key = String(id[id.index(after: colon)...])
        return key.isEmpty ? nil : (kind, key)
    }
}

extension GroceryStore {
    /// Everything worth finding from the Home Screen. Past items already on the list appear once, as list items.
    func spotlightEntries() -> [SpotlightEntry] {
        var entries: [SpotlightEntry] = meals.map { meal in
            let names = meal.ingredients.map(\.name)
            return SpotlightEntry(kind: .meal, key: meal.id.uuidString,
                                  title: meal.name.isEmpty ? "Untitled meal" : meal.name,
                                  detail: names.isEmpty ? "Saved meal" : "Meal: " + names.formatted(.list(type: .and)),
                                  keywords: ["meal", "recipe"] + names)
        }
        for item in items {
            let shop = shopName(for: item.shopID)
            let state = item.isChecked ? "Checked off" : "On your list"
            entries.append(SpotlightEntry(kind: .item, key: item.id.uuidString, title: item.name,
                                          detail: [state + (shop.map { " at \($0)" } ?? ""), item.note].compactMap { $0 }.joined(separator: " · "),
                                          keywords: ["grocery", "list", item.aisle.rawValue] + (shop.map { [$0] } ?? [])))
        }
        let listed = Set(items.map { $0.name.lowercased() })
        for past in history where !listed.contains(past.name.lowercased()) {
            var parts = ["Not on your list"]
            if let shop = shopName(for: past.shopID) { parts.append("last at \(shop)") }
            if let price = past.price { parts.append(Price.format(price)) }
            entries.append(SpotlightEntry(kind: .past, key: past.name, title: past.name,
                                          detail: parts.joined(separator: " · "),
                                          keywords: ["grocery", "buy again", past.aisle.rawValue]))
        }
        return entries
    }
}
