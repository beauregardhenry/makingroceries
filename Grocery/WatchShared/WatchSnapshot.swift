import Foundation

/// What the iPhone sends the Apple Watch: each store's list, already in walking order.
struct WatchSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var quantity: Int
        var note: String?
        var isChecked: Bool
    }

    struct Group: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var items: [Entry]
        var remaining: Int { items.filter { !$0.isChecked }.count }
    }

    var groups: [Group]
    var date = Date()

    static let contextKey = "snapshot"
    static let toggleKey = "toggle"
    /// The watch screen stays small and fast, so very long lists are cut.
    static let maxItemsPerGroup = 60
}
