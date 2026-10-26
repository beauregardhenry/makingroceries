import Foundation
import Observation

enum Aisle: String, CaseIterable, Codable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy & Eggs"
    case meat = "Meat & Seafood"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case drinks = "Drinks"
    case household = "Household"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .produce: "carrot"
        case .dairy: "cup.and.saucer"
        case .meat: "fish"
        case .bakery: "birthday.cake"
        case .pantry: "takeoutbag.and.cup.and.straw"
        case .frozen: "snowflake"
        case .drinks: "waterbottle"
        case .household: "sparkles"
        case .other: "cart"
        }
    }
}

struct GroceryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Int = 1
    var aisle: Aisle = .other
    var isChecked = false
    /// Nil means the item isn't tied to a particular store.
    var shopID: UUID?
}

struct Shop: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String

    static let defaultNames = ["Kroger", "Walmart", "Chinese Grocery"]
    static let presetNames = [
        "Kroger", "Walmart", "Chinese Grocery", "Costco", "Target", "Aldi", "Trader Joe's",
        "Whole Foods", "Publix", "Safeway", "Sam's Club", "Asian Market", "Farmers Market",
    ]
}

@Observable
final class GroceryStore {
    var items: [GroceryItem] = [] {
        didSet { save() }
    }

    var shops: [Shop] = [] {
        didSet { saveShops() }
    }

    private let url = URL.documentsDirectory.appending(path: "grocery.json")
    private let shopsURL = URL.documentsDirectory.appending(path: "shops.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([GroceryItem].self, from: data) {
            items = decoded
        } else {
            items = [
                GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
                GroceryItem(name: "Milk", aisle: .dairy),
                GroceryItem(name: "Sourdough", aisle: .bakery),
            ]
        }

        if let data = try? Data(contentsOf: shopsURL),
           let decoded = try? JSONDecoder().decode([Shop].self, from: data) {
            shops = decoded
        } else {
            shops = Shop.defaultNames.map { Shop(name: $0) }
        }
    }

    func add(name: String, quantity: Int, aisle: Aisle, shopID: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(GroceryItem(name: trimmed, quantity: quantity, aisle: aisle, shopID: shopID))
    }

    /// Adds a store unless the name is blank or already taken (ignoring case).
    @discardableResult
    func addShop(named name: String) -> Shop? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !shops.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let shop = Shop(name: trimmed)
        shops.append(shop)
        return shop
    }

    /// Items from a deleted store stay on the list, just without a store.
    func deleteShop(_ shop: Shop) {
        shops.removeAll { $0.id == shop.id }
        items = items.map { item in
            var item = item
            if item.shopID == shop.id { item.shopID = nil }
            return item
        }
    }

    func shopName(for id: UUID?) -> String? {
        id.flatMap { id in shops.first { $0.id == id }?.name }
    }

    func move(_ item: GroceryItem, to shopID: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].shopID = shopID
    }

    func toggle(_ item: GroceryItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].isChecked.toggle()
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
    }

    /// Clears checked items, limited to those `include` accepts (all by default).
    func clearChecked(where include: (GroceryItem) -> Bool = { _ in true }) {
        items.removeAll { $0.isChecked && include($0) }
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    private func saveShops() {
        try? JSONEncoder().encode(shops).write(to: shopsURL, options: .atomic)
    }
}
