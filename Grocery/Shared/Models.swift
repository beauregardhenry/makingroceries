import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// Brand, size, coupon or sale details.
    var note: String?
    /// File name of the item's photo, see `Storage.photos`.
    var photo: String?
}

struct PricePoint: Codable, Equatable {
    var shopID: UUID?
    var price: Double
    var date: Date
}

/// Something added before, remembered for autocomplete, "buy again" and price comparison.
struct PastItem: Identifiable, Codable, Equatable {
    var name: String
    var aisle: Aisle
    var shopID: UUID?
    var price: Double?
    var count = 1
    var lastUsed = Date()
    var priceHistory: [PricePoint]?
    /// When it was checked off, at most one per day, newest last.
    var purchases: [Date]?

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
    /// Measured ingredients, like "2 cups flour": the amount and its unit.
    var amount: Double?
    var unit: String?

    /// What to put on the list for a bigger or smaller batch. Counted items scale their quantity
    /// (never below 1); measured ones stay one item with the scaled amount as a note.
    func scaled(by factor: Double) -> (quantity: Int, note: String?) {
        if let amount, let unit {
            return (1, factor == 1 ? Amount.text(amount, unit: unit) : Amount.text(amount * factor, unit: unit))
        }
        return (max(1, Int((Double(quantity) * factor - 0.0001).rounded(.up))), nil)
    }
}

struct Meal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var ingredients: [MealIngredient] = []
}

/// An item that returns to the list on its own every few days.
struct RecurringItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity = 1
    var aisle: Aisle = .other
    var shopID: UUID?
    var everyDays: Int
    var nextDue: Date
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
    var latitude: Double?
    var longitude: Double?
    /// Notify when arriving here with items on the list.
    var remindOnArrival: Bool?

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    // Stores saved before aisle maps and locations existed lack those keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aisleOrder = try c.decodeIfPresent([Aisle].self, forKey: .aisleOrder) ?? Aisle.allCases
        aisleLabels = try c.decodeIfPresent([String: String].self, forKey: .aisleLabels) ?? [:]
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        remindOnArrival = try c.decodeIfPresent(Bool.self, forKey: .remindOnArrival)
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

    var hasLocation: Bool { latitude != nil && longitude != nil }

    static let defaultNames = ["Kroger", "Walmart", "Chinese Grocery"]
    static let presetNames = [
        "Kroger", "Walmart", "Chinese Grocery", "Costco", "Target", "Aldi", "Trader Joe's",
        "Whole Foods", "Publix", "Safeway", "Sam's Club", "Asian Market", "Farmers Market",
    ]
}

/// Everything in one file, for backup and restore.
struct Backup: Codable {
    var version = 1
    var items: [GroceryItem]
    var shops: [Shop]
    var favorites: [Favorite]
    var meals: [Meal]
    var history: [PastItem]
    var recurring: [RecurringItem]
}

enum Storage {
    static let groupID = "group.com.beauregardhenry.makingroceries"
    static let fileNames = ["grocery", "shops", "favorites", "meals", "history", "recurring"]

    /// The app group container when there is one, so widgets and Siri see the same data;
    /// otherwise Documents. Files from earlier versions are copied across once.
    static let directory: URL = {
        let docs = URL.documentsDirectory
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return docs
        }
        for name in fileNames {
            let old = docs.appending(path: "\(name).json")
            let new = group.appending(path: "\(name).json")
            if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) {
                try? FileManager.default.copyItem(at: old, to: new)
            }
        }
        return group
    }()

    static func url(_ name: String) -> URL { directory.appending(path: "\(name).json") }

    static var photos: URL {
        let url = directory.appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Observable
final class GroceryStore {
    var items: [GroceryItem] = [] {
        didSet { write(items, to: Storage.url("grocery")); refreshWidgets() }
    }

    var shops: [Shop] = [] {
        didSet { write(shops, to: Storage.url("shops")); refreshWidgets() }
    }

    var favorites: [Favorite] = [] {
        didSet { write(favorites, to: Storage.url("favorites")) }
    }

    var meals: [Meal] = [] {
        didSet { write(meals, to: Storage.url("meals")) }
    }

    var history: [PastItem] = [] {
        didSet { write(history, to: Storage.url("history")) }
    }

    var recurring: [RecurringItem] = [] {
        didSet { write(recurring, to: Storage.url("recurring")) }
    }

    init() {
        load()
        if read([PastItem].self, from: Storage.url("history")) == nil {
            // First run with history: start from what's already on the list.
            history = items.map { PastItem(name: $0.name, aisle: $0.aisle, shopID: $0.shopID, price: $0.price) }
        }
        applyRecurring()
    }

    /// Re-reads everything from disk, for changes made by a widget or Siri.
    func reload() {
        load()
        applyRecurring()
    }

    private func load() {
        items = read([GroceryItem].self, from: Storage.url("grocery")) ?? [
            GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
            GroceryItem(name: "Milk", aisle: .dairy),
            GroceryItem(name: "Sourdough", aisle: .bakery),
        ]
        shops = read([Shop].self, from: Storage.url("shops")) ?? Shop.defaultNames.map { Shop(name: $0) }
        favorites = read([Favorite].self, from: Storage.url("favorites")) ?? []
        meals = read([Meal].self, from: Storage.url("meals")) ?? []
        history = read([PastItem].self, from: Storage.url("history")) ?? []
        recurring = read([RecurringItem].self, from: Storage.url("recurring")) ?? []
    }

    // MARK: Items

    func add(name: String, quantity: Int, aisle: Aisle, shopID: UUID? = nil, price: Double? = nil, note: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(GroceryItem(name: trimmed, quantity: quantity, aisle: aisle, shopID: shopID, price: price, note: note))
        remember(name: trimmed, aisle: aisle, shopID: shopID, price: price)
    }

    /// Adds an item, or raises the quantity of the same unchecked item already in that store.
    /// A missing aisle or price comes from history, then a keyword guess. With `inferShop`,
    /// a missing store comes from history too. Near-misses of a known name ("tomatos") are
    /// corrected to it.
    func addOrBump(name: String, quantity: Int = 1, aisle: Aisle? = nil, shopID: UUID?,
                   price: Double? = nil, inferShop: Bool = false, note: String? = nil) {
        let typed = name.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        let trimmed = canonicalName(for: typed)
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
            shopID: shop, price: price ?? past?.price, note: note)
    }

    func toggle(_ item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isChecked.toggle()
        if items[i].isChecked { recordPurchase(of: items[i].name) }
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
        removePhotoIfUnused(item.photo)
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

    /// Saves edits from the details screen.
    func update(_ item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let oldPhoto = items[i].photo
        items[i] = item
        if oldPhoto != item.photo { removePhotoIfUnused(oldPhoto) }
        remember(name: item.name, aisle: item.aisle, shopID: item.shopID, price: item.price, countsAsUse: false)
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

    /// Unchecked items for a widget or Siri: one store's, in its walking order, or everything.
    func widgetItems(shopID: UUID?) -> [GroceryItem] {
        let shop = shop(for: shopID)
        let pool = items.filter { !$0.isChecked && (shopID == nil || $0.shopID == shopID) }
        let order = shop?.orderedAisles ?? Aisle.allCases
        return pool.sorted { (order.firstIndex(of: $0.aisle) ?? 0) < (order.firstIndex(of: $1.aisle) ?? 0) }
    }

    private func removePhotoIfUnused(_ name: String?) {
        guard let name, !items.contains(where: { $0.photo == name }) else { return }
        try? FileManager.default.removeItem(at: Storage.photos.appending(path: name))
    }

    // MARK: History, autocomplete and buy again

    func pastItem(named name: String) -> PastItem? {
        history.first { Self.same($0.name, name) }
    }

    func resolveAisle(for name: String) -> Aisle {
        pastItem(named: name)?.aisle ?? Aisle.guess(fromCategories: [name]) ?? .other
    }

    private func remember(name: String, aisle: Aisle, shopID: UUID?, price: Double?, countsAsUse: Bool = true) {
        let point = price.map { PricePoint(shopID: shopID, price: $0, date: Date()) }
        if let i = history.firstIndex(where: { Self.same($0.name, name) }) {
            history[i].aisle = aisle
            history[i].shopID = shopID
            if let price { history[i].price = price }
            if let point { Self.append(point, to: &history[i]) }
            if countsAsUse {
                history[i].count += 1
                history[i].lastUsed = Date()
            }
        } else {
            var past = PastItem(name: name, aisle: aisle, shopID: shopID, price: price)
            if let point { Self.append(point, to: &past) }
            history.append(past)
        }
    }

    /// Keeps a short price trail, skipping a repeat of the latest price at the same store.
    private static func append(_ point: PricePoint, to past: inout PastItem) {
        var trail = past.priceHistory ?? []
        if let last = trail.last(where: { $0.shopID == point.shopID }), abs(last.price - point.price) < 0.005 { return }
        trail.append(point)
        past.priceHistory = Array(trail.suffix(30))
    }

    private func recordPurchase(of name: String) {
        guard let i = history.firstIndex(where: { Self.same($0.name, name) }) else { return }
        var dates = history[i].purchases ?? []
        if let last = dates.last, Calendar.current.isDateInToday(last) { return }
        dates.append(Date())
        history[i].purchases = Array(dates.suffix(12))
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

    /// Items you buy at a steady pace that are about due, judged from when you checked them off.
    func dueItems(limit: Int = 4, now: Date = Date()) -> [PastItem] {
        history.compactMap { past -> (PastItem, Double)? in
            guard let dates = past.purchases?.sorted(), dates.count >= 3, !isOnList(past.name) else { return nil }
            let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
            let average = gaps.reduce(0, +) / Double(gaps.count)
            guard average >= 86_400 else { return nil }
            let ratio = now.timeIntervalSince(dates.last!) / average
            return ratio >= 0.85 ? (past, ratio) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit).map(\.0)
    }

    /// A short hint when the same item cost less at another store you've priced it in.
    func priceHint(for item: GroceryItem) -> String? {
        guard let trail = pastItem(named: item.name)?.priceHistory else { return nil }
        var latest: [UUID?: PricePoint] = [:]
        for point in trail.sorted(by: { $0.date < $1.date }) { latest[point.shopID] = point }
        let named = latest.values.filter { shop(for: $0.shopID) != nil }
        guard named.count >= 2, let best = named.min(by: { $0.price < $1.price }) else { return nil }
        if let price = item.price, best.price >= price - 0.005 { return nil }
        if best.shopID == item.shopID { return nil }
        let cost = best.price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        return "Cheaper at \(shopName(for: best.shopID) ?? "another store"): \(cost)"
    }

    // MARK: Spelling

    /// The known spelling of a name (from the list or history) when the typed one is the same
    /// word in another case, singular or plural, or a one- or two-letter typo; otherwise as typed.
    func canonicalName(for typed: String) -> String {
        let known = items.map(\.name) + history.map(\.name)
        if let exact = known.first(where: { Self.same($0, typed) }) { return exact }
        let key = Self.stem(typed)
        if let match = known.first(where: { Self.stem($0) == key }) { return match }
        guard key.count >= 5 else { return typed }
        let allowed = key.count >= 9 ? 2 : 1
        let near = known
            .map { ($0, Self.distance(Self.stem($0), key)) }
            .filter { $0.1 <= allowed }
            .min { $0.1 < $1.1 }
        return near?.0 ?? typed
    }

    static func stem(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.count > 4, s.hasSuffix("ies") { s = String(s.dropLast(3)) + "y" }
        else if s.count > 4, s.hasSuffix("oes") { s = String(s.dropLast(2)) }
        else if s.count > 3, s.hasSuffix("s"), !s.hasSuffix("ss") { s = String(s.dropLast()) }
        return s
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
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

    func addToList(_ meal: Meal, shopID: UUID?, scale: Double = 1) {
        for ingredient in meal.ingredients {
            let scaled = ingredient.scaled(by: scale)
            addOrBump(name: ingredient.name, quantity: scaled.quantity, aisle: ingredient.aisle,
                      shopID: shopID, inferShop: shopID == nil, note: scaled.note)
        }
    }

    /// A meal from ingredient lines (pasted, photographed or from a web page).
    func makeMeal(named name: String, fromLines lines: String) -> Meal {
        let ingredients = RecipeParser.fromText(lines).map { line in
            MealIngredient(name: line.name, quantity: line.quantity, aisle: resolveAisle(for: line.name),
                           amount: line.amount, unit: line.unit)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Meal(name: trimmed.isEmpty ? "Imported recipe" : trimmed, ingredients: ingredients)
    }

    // MARK: Repeating items

    func recurrence(for item: GroceryItem) -> RecurringItem? {
        recurring.first { Self.same($0.name, item.name) }
    }

    /// Makes `item` come back every `days` days, or stops it when `days` is nil.
    func setRepeat(for item: GroceryItem, everyDays days: Int?) {
        recurring.removeAll { Self.same($0.name, item.name) }
        guard let days else { return }
        let next = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        recurring.append(RecurringItem(name: item.name, quantity: item.quantity, aisle: item.aisle,
                                       shopID: item.shopID, everyDays: days, nextDue: next))
    }

    /// Puts anything due back on the list and schedules its next return.
    func applyRecurring(now: Date = Date()) {
        var changed = false
        for i in recurring.indices where recurring[i].nextDue <= now {
            let entry = recurring[i]
            if !isOnList(entry.name) {
                add(name: entry.name, quantity: entry.quantity, aisle: entry.aisle, shopID: entry.shopID)
            }
            var next = entry.nextDue
            while next <= now { next = Calendar.current.date(byAdding: .day, value: entry.everyDays, to: next) ?? now.addingTimeInterval(86_400) }
            recurring[i].nextDue = next
            changed = true
        }
        _ = changed
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

    // MARK: Backup

    func makeBackup() -> Backup {
        Backup(items: items, shops: shops, favorites: favorites, meals: meals, history: history, recurring: recurring)
    }

    func restore(_ backup: Backup) {
        items = backup.items
        shops = backup.shops
        favorites = backup.favorites
        meals = backup.meals
        history = backup.history
        recurring = backup.recurring
    }

    // MARK: Storage

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    private func refreshWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
