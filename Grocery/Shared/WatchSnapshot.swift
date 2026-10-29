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

// MARK: Messages between the phone and the watch

// In an extension, so the struct keeps its memberwise initializer.
extension WatchSnapshot {

    /// What the phone passes to `updateApplicationContext`.
    func context() throws -> [String: Any] {
        [Self.contextKey: try JSONEncoder().encode(self)]
    }

    /// The snapshot in an application context from the phone, or nil if it has none or can't be read.
    init?(context: [String: Any]) {
        guard let data = context[Self.contextKey] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return nil }
        self = snapshot
    }

    /// What the watch sends when an item is checked or unchecked on the wrist.
    static func toggleMessage(for entryID: String) -> [String: Any] {
        [toggleKey: entryID]
    }

    /// The item a message from the watch asks to check or uncheck.
    static func toggledID(in message: [String: Any]) -> String? {
        message[toggleKey] as? String
    }

    /// Flips one item on the watch, so the change shows before the phone confirms it.
    mutating func toggle(entryID: String) {
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.id == entryID }) {
                groups[g].items[i].isChecked.toggle()
            }
        }
    }
}
