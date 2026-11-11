import Foundation

/// Which list the list screen is showing.
enum ShopFilter: Equatable {
    case all
    case shop(UUID)
    /// Travel, Clothing or Registry, each kept off every other list.
    case list(SeparateList)

    init(raw: String) {
        if let list = SeparateList(rawValue: raw) {
            self = .list(list)
        } else {
            self = UUID(uuidString: raw).map(ShopFilter.shop) ?? .all
        }
    }

    /// The list new items on this screen belong to, if it is one of the separate lists.
    var separateList: SeparateList? {
        if case .list(let list) = self { list } else { nil }
    }

    var raw: String {
        switch self {
        case .all: ""
        case .list(let list): list.rawValue
        case .shop(let id): id.uuidString
        }
    }
}

/// One chip on the store bar after All: a store, Travel, Clothing or Registry.
enum ChipEntry: Hashable {
    case list(SeparateList)
    case shop(UUID)

    /// The list screen this chip opens.
    var filter: ShopFilter {
        switch self {
        case .list(let list): .list(list)
        case .shop(let id): .shop(id)
        }
    }
}

/// Where Travel, Clothing and Registry sit among the stores. The stores' own order is saved with the stores;
/// each list is saved as how many stores come before it. Negative means after every store, with -1 first, -2
/// after it and so on, so the lists keep their order at the end.
enum ChipOrder {
    /// The saved setting for a list's place. Travel's name is from when it was the only one.
    static func key(_ list: SeparateList) -> String {
        list == .travel ? "travelPosition" : "\(list.rawValue)Position"
    }

    /// Where a list sits until you move it: after every store, in the order of `SeparateList.allCases`.
    static func defaultPosition(_ list: SeparateList) -> Int {
        -1 - (SeparateList.allCases.firstIndex(of: list) ?? 0)
    }

    static func entries(shops: [Shop], positions: [SeparateList: Int] = [:]) -> [ChipEntry] {
        let count = shops.count
        func resolved(_ position: Int) -> Int { position < 0 ? count : min(position, count) }
        // At the end, -1 comes before -2.
        var floating: [(entry: ChipEntry, spot: Int, tie: Int)] = SeparateList.allCases.map { list in
            let position = positions[list] ?? defaultPosition(list)
            return (.list(list), resolved(position), position < 0 ? -position : 0)
        }
        floating.sort { ($0.spot, $0.tie) < ($1.spot, $1.tie) }
        var result: [ChipEntry] = []
        for index in 0...count {
            result += floating.filter { $0.spot == index }.map(\.entry)
            if index < count { result.append(.shop(shops[index].id)) }
        }
        return result
    }

    /// The saved place of a list after the chips were arranged into `entries`.
    static func position(of entries: [ChipEntry], list: SeparateList) -> Int {
        guard let spot = entries.firstIndex(of: .list(list)) else { return defaultPosition(list) }
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
