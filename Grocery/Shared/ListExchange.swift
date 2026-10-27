import Foundation

/// A list packed into a small file, for sending to family by iMessage, AirDrop or email.
struct ListExport: Codable {
    struct Item: Codable {
        var id: UUID
        var name: String
        var quantity: Int
        var aisle: Aisle
        var isChecked: Bool
        var shopName: String?
        var price: Double?
        var note: String?
    }

    var version = 1
    var exportedAt = Date()
    /// Who it's from, for the "from Jeff" in the import prompt.
    var from: String?
    var items: [Item]

    static let fileExtension = "makinglist"
    static let typeIdentifier = "com.beauregardhenry.makingroceries.list"
}

struct ImportSummary: Equatable {
    var added = 0
    var markedBought = 0
    var unchanged = 0
    var newStores: [String] = []
}

extension GroceryStore {
    func makeExport(shopID: UUID? = nil, onlyUnchecked: Bool = false, from: String? = nil) -> ListExport {
        let chosen = items.filter { (shopID == nil || $0.shopID == shopID) && (!onlyUnchecked || !$0.isChecked) }
        return ListExport(from: from, items: chosen.map {
            .init(id: $0.id, name: $0.name, quantity: $0.quantity, aisle: $0.aisle, isChecked: $0.isChecked,
                  shopName: shopName(for: $0.shopID), price: $0.price, note: $0.note)
        })
    }

    /// Writes the export to a temporary file and returns it, ready to share.
    func exportFile(_ export: ListExport) -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "Groceries-\(stamp).\(ListExport.fileExtension)")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    static func readExport(from url: URL) -> ListExport? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ListExport.self, from: data)
    }

    /// Merges a received list into yours. New items are added. Anything the sender already bought is
    /// marked bought here too (never un-bought). Items you already have, matched by their shared id or
    /// by name in the same store, aren't duplicated. With `apply` false it only counts what would change.
    @discardableResult
    func mergeImport(_ export: ListExport, apply: Bool = true) -> ImportSummary {
        var summary = ImportSummary()
        var shopIDs: [String: UUID] = [:]
        for shop in shops { shopIDs[shop.name.lowercased()] = shop.id }

        for incoming in export.items {
            var shopID: UUID?
            if let name = incoming.shopName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                let key = name.lowercased()
                if let known = shopIDs[key] {
                    shopID = known
                } else {
                    if !summary.newStores.contains(name) { summary.newStores.append(name) }
                    if apply, let created = addShop(named: name) { shopIDs[key] = created.id; shopID = created.id }
                }
            }

            let match = items.firstIndex { $0.id == incoming.id }
                ?? items.firstIndex { $0.shopID == shopID && $0.name.caseInsensitiveCompare(incoming.name) == .orderedSame }

            if let i = match {
                if incoming.isChecked && !items[i].isChecked {
                    summary.markedBought += 1
                    if apply { items[i].isChecked = true }
                } else {
                    summary.unchanged += 1
                }
            } else {
                summary.added += 1
                if apply {
                    var item = GroceryItem(name: incoming.name, quantity: incoming.quantity, aisle: incoming.aisle,
                                           isChecked: incoming.isChecked, shopID: shopID, price: incoming.price, note: incoming.note)
                    item.id = incoming.id
                    items.append(item)
                }
            }
        }
        return summary
    }
}
