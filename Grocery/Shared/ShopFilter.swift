import Foundation

/// Which list the list screen is showing.
enum ShopFilter: Equatable {
    case all
    /// Items that aren't tied to a particular store.
    case anyStore
    case shop(UUID)
    /// Items for a trip, kept off every other list.
    case travel

    init(raw: String) {
        switch raw {
        case "any": self = .anyStore
        case "travel": self = .travel
        case let raw: self = UUID(uuidString: raw).map(ShopFilter.shop) ?? .all
        }
    }

    var raw: String {
        switch self {
        case .all: ""
        case .anyStore: "any"
        case .travel: "travel"
        case .shop(let id): id.uuidString
        }
    }
}

/// One chip on the store bar after All and Anywhere: a store, or Travel.
enum ChipEntry: Hashable {
    case travel
    case shop(UUID)
}

/// Where Travel sits among the stores. The stores' own order is saved with the stores; Travel's place is
/// saved as how many stores come before it, with -1 meaning last.
enum ChipOrder {
    static let key = "travelPosition"
    static let last = -1

    static func entries(shops: [Shop], travelPosition: Int) -> [ChipEntry] {
        var entries = shops.map { ChipEntry.shop($0.id) }
        let spot = travelPosition < 0 ? entries.count : min(travelPosition, entries.count)
        entries.insert(.travel, at: spot)
        return entries
    }

    /// The saved position after the chips were arranged into `entries`.
    static func position(of entries: [ChipEntry]) -> Int {
        guard let spot = entries.firstIndex(of: .travel), spot < entries.count - 1 else { return last }
        return spot
    }

    /// The stores in the order `entries` puts them.
    static func shops(_ shops: [Shop], arrangedBy entries: [ChipEntry]) -> [Shop] {
        entries.compactMap { entry in
            if case .shop(let id) = entry { return shops.first { $0.id == id } }
            return nil
        }
    }
}
