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
    /// Price of one unit, if known.
    var price: Double?
}

/// Something added before, remembered for autocomplete and "buy again".
struct PastItem: Identifiable, Codable, Equatable {
    var name: String
    var aisle: Aisle
    var shopID: UUID?
    var price: Double?
    var count = 1
    var lastUsed = Date()

    var id: String { name.lowercased() }
}

/// A staple on the "usual" list.
struct Favorite: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity = 1
    var aisle: Aisle = .other
}

struct MealIngredient: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity = 1
    var aisle: Aisle = .other
}

struct Meal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var ingredients: [MealIngredient] = []
}

/// A checked item removed by Clear Done, with where it was, so it can be put back.
struct ClearedItem {
    let index: Int
    let item: GroceryItem
}

struct Shop: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    /// The order this store's aisles are walked in; may be missing newer aisles (see `orderedAisles`).
    var aisleOrder: [Aisle] = Aisle.allCases
    /// Optional per-aisle labels such as "Aisle 7", keyed by `Aisle.rawValue`.
    var aisleLabels: [String: String] = [:]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    // Stores saved before aisle maps existed have no order or labels.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aisleOrder = try c.decodeIfPresent([Aisle].self, forKey: .aisleOrder) ?? Aisle.allCases
        aisleLabels = try c.decodeIfPresent([String: String].self, forKey: .aisleLabels) ?? [:]
    }

    /// Every aisle exactly once: the saved order first, then any aisle it doesn't mention.
    var orderedAisles: [Aisle] {
        var seen = Set<Aisle>()
        let saved = aisleOrder.filter { seen.insert($0).inserted }
        return saved + Aisle.allCases.filter { !seen.contains($0) }
    }

    func label(for aisle: Aisle) -> String? {
        let text = aisleLabels[aisle.rawValue]?.trimmingCharacters(in: .whitespaces)
        return (text?.isEmpty == false) ? text : nil
    }

    static let defaultNames = ["Kroger", "Walmart", "Chinese Grocery"]
    static let presetNames = [
        "Kroger", "Walmart", "Chinese Grocery", "Costco", "Target", "Aldi", "Trader Joe's",
        "Whole Foods", "Publix", "Safeway", "Sam's Club", "Asian Market", "Farmers Market",
    ]
}

@Observable
final class GroceryStore {
    var items: [GroceryItem] = [] {
        didSet { write(items, to: itemsURL) }
    }

    var shops: [Shop] = [] {
        didSet { write(shops, to: shopsURL) }
    }

    var favorites: [Favorite] = [] {
        didSet { write(favorites, to: favoritesURL) }
    }

    var meals: [Meal] = [] {
        didSet { write(meals, to: mealsURL) }
    }

    var history: [PastItem] = [] {
        didSet { write(history, to: historyURL) }
    }

    private let itemsURL = URL.documentsDirectory.appending(path: "grocery.json")
    private let shopsURL = URL.documentsDirectory.appending(path: "shops.json")
    private let favoritesURL = URL.documentsDirectory.appending(path: "favorites.json")
    private let mealsURL = URL.documentsDirectory.appending(path: "meals.json")
    private let historyURL = URL.documentsDirectory.appending(path: "history.json")

    init() {
        items = read([GroceryItem].self, from: itemsURL) ?? [
            GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
            GroceryItem(name: "Milk", aisle: .dairy),
            GroceryItem(name: "Sourdough", aisle: .bakery),
        ]
        shops = read([Shop].self, from: shopsURL) ?? Shop.defaultNames.map { Shop(name: $0) }
        favorites = read([Favorite].self, from: favoritesURL) ?? []
        meals = read([Meal].self, from: mealsURL) ?? []
        // First run with history: start from what's already on the list.
        history = read([PastItem].self, from: historyURL)
            ?? items.map { PastItem(name: $0.name, aisle: $0.aisle, shopID: $0.shopID, price: $0.price) }
    }

    // MARK: Items

    func add(name: String, quantity: Int, aisle: Aisle, shopID: UUID? = nil, price: Double? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(GroceryItem(name: trimmed, quantity: quantity, aisle: aisle, shopID: shopID, price: price))
        remember(name: trimmed, aisle: aisle, shopID: shopID, price: price)
    }

    /// Adds an item, or raises the quantity of the same unchecked item already in that store.
    /// A missing aisle or price comes from history, then a keyword guess. With `inferShop`,
    /// a missing store comes from history too.
    func addOrBump(name: String, quantity: Int = 1, aisle: Aisle? = nil, shopID: UUID?,
                   price: Double? = nil, inferShop: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let past = pastItem(named: trimmed)
        var shop = shopID
        if shop == nil, inferShop, let remembered = past?.shopID, self.shop(for: remembered) != nil {
            shop = remembered
        }
        if let i = items.firstIndex(where: { !$0.isChecked && $0.shopID == shop && Self.same($0.name, trimmed) }) {
            items[i].quantity += quantity
            return
        }
        add(name: trimmed, quantity: quantity, aisle: aisle ?? resolveAisle(for: trimmed),
            shopID: shop, price: price ?? past?.price)
    }

    func toggle(_ item: GroceryItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].isChecked.toggle()
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
    }

    func move(_ item: GroceryItem, to shopID: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].shopID = shopID
    }

    func setPrice(_ price: Double?, for item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].price = price
        remember(name: item.name, aisle: item.aisle, shopID: item.shopID, price: price, countsAsUse: false)
    }

    /// Clears checked items, limited to those `include` accepts (all by default).
    /// Returns what was removed so the caller can offer undo.
    @discardableResult
    func clearChecked(where include: (GroceryItem) -> Bool = { _ in true }) -> [ClearedItem] {
        let removed = items.enumerated().filter { $0.element.isChecked && include($0.element) }
            .map { ClearedItem(index: $0.offset, item: $0.element) }
        let ids = Set(removed.map(\.item.id))
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Puts cleared items back where they were.
    func restore(_ cleared: [ClearedItem]) {
        var restored = items
        for entry in cleared.sorted(by: { $0.index < $1.index }) {
            restored.insert(entry.item, at: min(entry.index, restored.count))
        }
        items = restored
    }

    func isOnList(_ name: String) -> Bool {
        items.contains { !$0.isChecked && Self.same($0.name, name) }
    }

    // MARK: History, autocomplete and buy again

    func pastItem(named name: String) -> PastItem? {
        history.first { Self.same($0.name, name) }
    }

    func resolveAisle(for name: String) -> Aisle {
        pastItem(named: name)?.aisle ?? Aisle.guess(fromCategories: [name]) ?? .other
    }

    private func remember(name: String, aisle: Aisle, shopID: UUID?, price: Double?, countsAsUse: Bool = true) {
        if let i = history.firstIndex(where: { Self.same($0.name, name) }) {
            history[i].aisle = aisle
            history[i].shopID = shopID
            if let price { history[i].price = price }
            if countsAsUse {
                history[i].count += 1
                history[i].lastUsed = Date()
            }
        } else {
            history.append(PastItem(name: name, aisle: aisle, shopID: shopID, price: price))
        }
    }

    /// Past items starting with `prefix`, most used first, skipping what's already on the list.
    func suggestions(for prefix: String, limit: Int = 6) -> [PastItem] {
        let prefix = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !prefix.isEmpty else { return [] }
        return history
            .filter { $0.name.lowercased().hasPrefix(prefix) && $0.name.lowercased() != prefix && !isOnList($0.name) }
            .sorted { ($0.count, $0.lastUsed) > ($1.count, $1.lastUsed) }
            .prefix(limit).map { $0 }
    }

    /// Past items not on the list now, most recent first.
    func buyAgain(limit: Int = 25) -> [PastItem] {
        history.filter { !isOnList($0.name) }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit).map { $0 }
    }

    // MARK: Usual items

    func addFavorite(name: String, quantity: Int = 1, aisle: Aisle? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !favorites.contains(where: { Self.same($0.name, trimmed) }) else { return }
        favorites.append(Favorite(name: trimmed, quantity: quantity, aisle: aisle ?? resolveAisle(for: trimmed)))
    }

    func addToList(_ favorite: Favorite, shopID: UUID?) {
        addOrBump(name: favorite.name, quantity: favorite.quantity, aisle: favorite.aisle,
                  shopID: shopID, inferShop: shopID == nil)
    }

    // MARK: Meals

    func addToList(_ meal: Meal, shopID: UUID?) {
        for ingredient in meal.ingredients {
            addOrBump(name: ingredient.name, quantity: ingredient.quantity, aisle: ingredient.aisle,
                      shopID: shopID, inferShop: shopID == nil)
        }
    }

    // MARK: Stores

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

    func shop(for id: UUID?) -> Shop? {
        id.flatMap { id in shops.first { $0.id == id } }
    }

    func shopName(for id: UUID?) -> String? {
        id.flatMap { id in shops.first { $0.id == id }?.name }
    }

    // MARK: Storage

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
