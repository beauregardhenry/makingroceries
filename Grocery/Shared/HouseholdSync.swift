import CryptoKit
import Foundation

/// What one phone sends another in the same household over the local network: its whole list, plus
/// anything removed or un-checked since its last send, so those changes reach the other phone too.
struct SyncPacket: Codable, Equatable {
    var version = 1
    var from: String
    var list: ListExport
    var removed: [UUID] = []
    var unchecked: [UUID] = []

    static func == (a: SyncPacket, b: SyncPacket) -> Bool {
        a.from == b.from && a.removed == b.removed && a.unchecked == b.unchecked
            && a.list.items.map(\.id) == b.list.items.map(\.id)
            && a.list.items.map(\.isChecked) == b.list.items.map(\.isChecked)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> SyncPacket? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SyncPacket.self, from: data)
    }
}

enum HouseholdCode {
    /// Codes are compared without case, spaces or dashes, so "Maple 42" and "maple-42" match.
    static func normalized(_ code: String) -> String {
        code.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isValid(_ code: String) -> Bool { normalized(code).count >= 4 }

    /// What a phone advertises on the network: a short hash, so the code itself is never broadcast.
    static func tag(for code: String) -> String {
        let digest = SHA256.hash(data: Data(("makingroceries:" + normalized(code)).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// A random code to start a household with, like "pear-4821".
    static func random() -> String {
        let words = ["apple", "basil", "berry", "carrot", "lemon", "mango", "olive", "peach", "pear", "plum", "thyme", "melon"]
        return "\(words.randomElement() ?? "pear")-\(Int.random(in: 1000...9999))"
    }
}

/// Notices what changed on this phone between sends: items removed, and items un-checked.
struct SyncTracker: Equatable {
    private var lastIDs: Set<UUID>
    private var lastChecked: Set<UUID>

    init(items: [GroceryItem] = []) {
        lastIDs = Set(items.map(\.id))
        lastChecked = Set(items.filter(\.isChecked).map(\.id))
    }

    /// What was removed or un-checked since the last call, then remembers `items` for next time.
    mutating func changes(in items: [GroceryItem]) -> (removed: [UUID], unchecked: [UUID]) {
        let ids = Set(items.map(\.id))
        let checked = Set(items.filter(\.isChecked).map(\.id))
        let removed = lastIDs.subtracting(ids)
        let unchecked = lastChecked.subtracting(checked).intersection(ids)
        lastIDs = ids
        lastChecked = checked
        return (removed.sorted { $0.uuidString < $1.uuidString }, unchecked.sorted { $0.uuidString < $1.uuidString })
    }
}

extension GroceryStore {
    func makeSyncPacket(from name: String, removed: [UUID] = [], unchecked: [UUID] = []) -> SyncPacket {
        SyncPacket(from: name, list: makeExport(from: name), removed: removed, unchecked: unchecked)
    }

    /// Applies a list from another phone in the household. Removals and un-checks it names happen here
    /// too; new items are added, and anything it bought is marked bought. Items it has already bought
    /// and you don't have aren't added, so clearing done items on one phone doesn't bring them back.
    @discardableResult
    func applySyncPacket(_ packet: SyncPacket) -> ImportSummary {
        let gone = Set(packet.removed), reopened = Set(packet.unchecked)
        if items.contains(where: { gone.contains($0.id) }) { items.removeAll { gone.contains($0.id) } }
        for i in items.indices where reopened.contains(items[i].id) && items[i].isChecked {
            items[i].isChecked = false
        }
        var list = packet.list
        list.items.removeAll { incoming in
            gone.contains(incoming.id)
                || (incoming.isChecked && !items.contains { $0.id == incoming.id })
        }
        // An item un-checked here since: don't let the other phone's older "bought" check it again.
        list.items = list.items.map { incoming in
            var incoming = incoming
            if reopened.contains(incoming.id) { incoming.isChecked = false }
            return incoming
        }
        return mergeImport(list)
    }
}
