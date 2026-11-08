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
