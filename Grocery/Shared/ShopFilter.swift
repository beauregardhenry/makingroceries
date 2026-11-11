import Foundation

/// Which list the list screen is showing.
enum ShopFilter: Equatable {
    case all
    case shop(UUID)
    /// Items for a trip, kept off every other list.
    case travel
    /// Clothing, organized by person and kept off every other list.
    case clothing
    /// Gifts, organized by person and kept off every other list.
    case registry

    init(raw: String) {
        switch raw {
        case "travel": self = .travel
        case "clothing": self = .clothing
        case "registry": self = .registry
        case let raw: self = UUID(uuidString: raw).map(ShopFilter.shop) ?? .all
        }
    }

    var raw: String {
        switch self {
        case .all: ""
        case .travel: "travel"
        case .clothing: "clothing"
        case .registry: "registry"
        case .shop(let id): id.uuidString
        }
    }
}

/// One chip on the store bar after All: a store, Travel or Clothing.
enum ChipEntry: Hashable {
    case travel
    case clothing
    case registry
    case shop(UUID)

    /// The chip's name and icon, and the list it opens. A store's come from the store itself.
    var title: String? {
        switch self {
        case .travel: "Travel"
        case .clothing: "Clothing"
        case .registry: "Registry"
        case .shop: nil
        }
    }

    var symbol: String? {
        switch self {
        case .travel: "airplane"
        case .clothing: "tshirt.fill"
        case .registry: "gift.fill"
        case .shop: nil
        }
    }

    var filter: ShopFilter {
        switch self {
        case .travel: .travel
        case .clothing: .clothing
        case .registry: .registry
        case .shop(let id): .shop(id)
        }
    }
}

/// Where Travel and Clothing sit among the stores. The stores' own order is saved with the stores; each of
/// these is saved as how many stores come before it. Negative means after every store, with -1 first and -2
/// after it, so the two keep their order at the end.
enum ChipOrder {
    static let key = "travelPosition"
    static let clothingKey = "clothingPosition"
    static let last = -1
    static let clothingLast = -2
    static let registryKey = "registryPosition"
    static let registryLast = -3

    static func entries(shops: [Shop], travelPosition: Int, clothingPosition: Int = ChipOrder.clothingLast,
                        registryPosition: Int = ChipOrder.registryLast) -> [ChipEntry] {
        let count = shops.count
        func resolved(_ position: Int) -> Int { position < 0 ? count : min(position, count) }
        // At the end, -1 comes before -2.
        var floating: [(entry: ChipEntry, spot: Int, tie: Int)] = [
            (.travel, resolved(travelPosition), travelPosition < 0 ? -travelPosition : 0),
            (.clothing, resolved(clothingPosition), clothingPosition < 0 ? -clothingPosition : 0),
            (.registry, resolved(registryPosition), registryPosition < 0 ? -registryPosition : 0),
        ]
        floating.sort { ($0.spot, $0.tie) < ($1.spot, $1.tie) }
        var result: [ChipEntry] = []
        for index in 0...count {
            result += floating.filter { $0.spot == index }.map(\.entry)
            if index < count { result.append(.shop(shops[index].id)) }
        }
        return result
    }

    /// The saved position of Travel or Clothing after the chips were arranged into `entries`.
    static func position(of entries: [ChipEntry], chip: ChipEntry = .travel) -> Int {
        guard let spot = entries.firstIndex(of: chip) else {
            return chip == .clothing ? clothingLast : chip == .registry ? registryLast : last
        }
        let storesBefore = entries[..<spot].filter { if case .shop = $0 { return true } else { return false } }.count
        let storesAfter = entries[(spot + 1)...].contains { if case .shop = $0 { return true } else { return false } }
        if storesAfter { return storesBefore }
        // After every store: -1 for the first of the chips at the end, -2 for the next.
        let tail = entries[..<spot].reversed().prefix { if case .shop = $0 { return false } else { return true } }
        return -1 - tail.count
    }

    /// The stores in the order `entries` puts them.
    static func shops(_ shops: [Shop], arrangedBy entries: [ChipEntry]) -> [Shop] {
        entries.compactMap { entry in
            if case .shop(let id) = entry { return shops.first { $0.id == id } }
            return nil
        }
    }
}
