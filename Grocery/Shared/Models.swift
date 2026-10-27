import Foundation

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
    /// Package size, e.g. 16 and "oz", for unit prices.
    var sizeAmount: Double?
    var sizeUnit: String?
    /// "Contains peanuts" and similar, from your avoid list.
    var warning: String?
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
    /// The barcode last scanned for it, so scanning it again can check it off.
    var barcode: String?
    var sizeAmount: Double?
    var sizeUnit: String?

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
    /// Adjust the aisle order from the order you check things off. Nil means on.
    var learnRoute: Bool?
    var routeEvents: [RouteEvent]?

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
        learnRoute = try c.decodeIfPresent(Bool.self, forKey: .learnRoute)
        routeEvents = try c.decodeIfPresent([RouteEvent].self, forKey: .routeEvents)
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
    var plan: [PlannedMeal]? = nil
    var stock: [StockEntry]? = nil
    var spending: [SpendRecord]? = nil
}
