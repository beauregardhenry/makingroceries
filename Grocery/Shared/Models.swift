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
    case pharmacy = "Pharmacy"
    // Non-food, for stores like Target, Home Depot and Lowe's.
    case hardware = "Hardware & Tools"
    case garden = "Garden & Outdoor"
    case electronics = "Electronics"
    case clothing = "Clothing"
    case home = "Home & Decor"
    case pet = "Pet"
    case toys = "Toys & Games"
    case other = "Other"

    var id: String { rawValue }

    /// One filled symbol per aisle, drawn white on the aisle's color (see `Aisle.tint`).
    var symbol: String {
        switch self {
        case .produce: "carrot.fill"
        case .dairy: "drop.fill"
        case .meat: "fish.fill"
        case .bakery: "basket.fill"
        case .pantry: "cabinet.fill"
        case .frozen: "snowflake"
        case .drinks: "waterbottle.fill"
        case .household: "bubbles.and.sparkles.fill"
        case .pharmacy: "cross.case.fill"
        case .hardware: "wrench.and.screwdriver.fill"
        case .garden: "tree.fill"
        case .electronics: "bolt.fill"
        case .clothing: "tshirt.fill"
        case .home: "lamp.floor.fill"
        case .pet: "pawprint.fill"
        case .toys: "teddybear.fill"
        case .other: "bag.fill"
        }
    }

    /// The aisles that only a general or hardware store has.
    static let nonFood: [Aisle] = [.hardware, .garden, .electronics, .clothing, .home, .pet, .toys]

    var isFood: Bool { !Aisle.nonFood.contains(self) }
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
    /// For a trip: kept off the everyday lists and shown under Travel. Nil means no.
    var isTravel: Bool?

    var forTravel: Bool { isTravel == true }
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
    var category: MealCategory?
    /// Makes well ahead and freezes well, so it's offered when company is coming. Nil means no.
    var freezes: Bool?

    var freezerFriendly: Bool { freezes == true }
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
    /// What the store sells; nil is a grocery store.
    var kind: ShopKind?

    init(id: UUID = UUID(), name: String, kind: ShopKind? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        if let kind { aisleOrder = kind.defaultOrder }
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
        kind = try c.decodeIfPresent(ShopKind.self, forKey: .kind)
    }

    /// Every aisle exactly once: the saved order first, then any aisle it doesn't mention. A newer aisle
    /// (like Pharmacy) goes just before Other when the saved order ends with Other, so Other stays last.
    var orderedAisles: [Aisle] {
        var seen = Set<Aisle>()
        var saved = aisleOrder.filter { seen.insert($0).inserted }
        let missing = Aisle.allCases.filter { !seen.contains($0) }
        if saved.last == .other {
            saved.insert(contentsOf: missing.filter { $0 != .other }, at: saved.count - 1)
            return saved
        }
        return saved + missing
    }

    func label(for aisle: Aisle) -> String? {
        let text = aisleLabels[aisle.rawValue]?.trimmingCharacters(in: .whitespaces)
        return (text?.isEmpty == false) ? text : nil
    }

    /// The aisle order a new or reset store of this kind starts with.
    var defaultOrder: [Aisle] { (kind ?? .grocery).defaultOrder }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    static let defaultNames = ["Kroger", "Walmart", "Chinese Grocery"]
    /// What items with no store are called: they can be bought anywhere.
    static let noStoreName = "Anywhere"
    static let presetNames = [
        "Kroger", "Walmart", "Chinese Grocery", "Costco", "Target", "Aldi", "Trader Joe's",
        "Whole Foods", "Publix", "Safeway", "Sam's Club", "Asian Market", "Farmers Market",
        "Home Depot", "Lowe's", "Best Buy", "Menards", "Ace Hardware", "Petco", "PetSmart",
    ]

    /// What a well-known store sells, from its name. Nil for a grocery store or one we don't know.
    static func kind(forName name: String) -> ShopKind? {
        let lower = name.lowercased()
        func has(_ names: [String]) -> Bool { names.contains { lower.contains($0) } }
        if has(["home depot", "lowe", "menards", "ace hardware", "harbor freight", "true value"]) { return .hardware }
        if has(["target", "walmart", "costco", "sam's club", "best buy", "kmart", "meijer", "fred meyer",
                "petco", "petsmart", "ikea", "bed bath", "dollar"]) { return .general }
        return nil
    }
}

/// What a store sells, which sets the order of its aisles to start with.
enum ShopKind: String, Codable, CaseIterable {
    case grocery, general, hardware

    var title: String {
        switch self {
        case .grocery: "Grocery store"
        case .general: "General store"
        case .hardware: "Hardware store"
        }
    }

    /// Food first for a general store, since you walk in through the grocery side; tools first for hardware.
    var defaultOrder: [Aisle] {
        switch self {
        case .grocery:
            return Aisle.allCases
        case .general:
            let food = Aisle.allCases.filter { $0.isFood && $0 != .other }
            return food + Aisle.nonFood + [.other]
        case .hardware:
            let first: [Aisle] = [.hardware, .garden, .home, .electronics]
            let rest = Aisle.allCases.filter { !first.contains($0) && $0 != .other }
            return first + rest + [.other]
        }
    }
}

/// How saved recipes are grouped.
enum MealCategory: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case soup = "Soups & Stews"
    case side = "Sides"
    case snack = "Snacks"
    case dessert = "Desserts"
    case drink = "Drinks"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch: "takeoutbag.and.cup.and.straw.fill"
        case .dinner: "fork.knife"
        case .soup: "cup.and.saucer.fill"
        case .side: "leaf.fill"
        case .snack: "popcorn.fill"
        case .dessert: "birthday.cake.fill"
        case .drink: "mug.fill"
        }
    }

    /// A guess from a recipe's name, so imported recipes don't all land in "Uncategorized".
    static func guess(fromName name: String) -> MealCategory? {
        let words = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ keys: [String]) -> Bool { keys.contains { key in words.contains(where: { $0.hasPrefix(key) }) } }
        if has(["soup", "stew", "chili", "chowder", "broth", "bisque"]) { return .soup }
        if has(["pancake", "waffle", "omelet", "omelette", "breakfast", "oatmeal", "granola", "muffin", "scone", "frittata", "french"]) { return .breakfast }
        if has(["cake", "cookie", "brownie", "pie", "dessert", "pudding", "cobbler", "cupcake", "fudge", "ice"]) { return .dessert }
        if has(["smoothie", "lemonade", "cocktail", "punch", "latte"]) { return .drink }
        if has(["dip", "hummus", "snack", "popcorn", "bites", "jerky"]) { return .snack }
        if has(["salad", "slaw", "side", "fries", "rice", "mashed", "coleslaw"]) { return .side }
        if has(["sandwich", "wrap", "sub", "burger", "quesadilla", "lunch"]) { return .lunch }
        return nil
    }
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
