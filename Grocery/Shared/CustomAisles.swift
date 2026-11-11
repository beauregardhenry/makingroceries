import Foundation

/// A section you name yourself ("Aisle 5", "Baking", "Bulk bins"), listed beside the built-in categories.
struct CustomAisle: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
}

/// One section of the list: a built-in category or one of your own aisles.
enum AisleSection: Hashable, Identifiable {
    case aisle(Aisle)
    case custom(UUID)

    var id: String {
        switch self {
        case .aisle(let aisle): aisle.rawValue
        case .custom(let id): "custom-\(id.uuidString)"
        }
    }
}

extension Shop {
    /// Every category in this store's walking order, with your custom aisles slotted in where you put them.
    /// A custom aisle with no saved spot goes just before Other.
    func orderedSections(custom: [CustomAisle]) -> [AisleSection] {
        var result = orderedAisles.map(AisleSection.aisle)
        for aisle in custom {
            let key = aisle.id.uuidString
            let anchor = customAnchors?[key]
            var index = result.firstIndex(of: .aisle(.other)) ?? result.count
            if let anchor {
                if anchor.isEmpty {
                    index = 0
                } else if let category = Aisle(rawValue: anchor), let at = result.firstIndex(of: .aisle(category)) {
                    index = at + 1
                }
            }
            // Aisles that follow the same category keep the order of your list.
            while index < result.count, case .custom(let other) = result[index], customAnchors?[other.uuidString] == anchor {
                index += 1
            }
            result.insert(.custom(aisle.id), at: index)
        }
        return result
    }

    /// Saves an order made by dragging: the categories keep their order, and each custom aisle remembers
    /// the category it follows.
    mutating func setSectionOrder(_ sections: [AisleSection]) {
        aisleOrder = sections.compactMap { if case .aisle(let aisle) = $0 { aisle } else { nil } }
        var anchors: [String: String] = [:]
        var previous = ""
        for section in sections {
            switch section {
            case .aisle(let aisle): previous = aisle.rawValue
            case .custom(let id): anchors[id.uuidString] = previous
            }
        }
        customAnchors = anchors
    }
}

extension GroceryStore {
    @discardableResult
    func addCustomAisle(named name: String) -> CustomAisle? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !customAisles.contains(where: { Self.same($0.name, trimmed) }),
              !Aisle.allCases.contains(where: { Self.same($0.rawValue, trimmed) }) else { return nil }
        let aisle = CustomAisle(name: trimmed)
        customAisles.append(aisle)
        return aisle
    }

    func customAisle(for id: UUID?) -> CustomAisle? {
        guard let id else { return nil }
        return customAisles.first { $0.id == id }
    }

    /// Items in a deleted aisle go back under their category.
    func deleteCustomAisle(_ id: UUID) {
        customAisles.removeAll { $0.id == id }
        for i in items.indices where items[i].customAisleID == id { items[i].customAisleID = nil }
        for i in shops.indices { shops[i].customAnchors?[id.uuidString] = nil }
    }

    /// The items grouped into sections in a store's order (or the default order), skipping empty ones.
    /// An item in one of your aisles shows there instead of under its category.
    func sectionGroups(_ items: [GroceryItem], shop: Shop?) -> [(section: AisleSection, items: [GroceryItem])] {
        let known = Set(customAisles.map(\.id))
        let order = shop?.orderedSections(custom: customAisles)
            ?? Shop(name: "").orderedSections(custom: customAisles)
        return order.compactMap { section in
            let matching: [GroceryItem]
            switch section {
            case .aisle(let aisle):
                matching = items.filter { $0.aisle == aisle && !($0.customAisleID.map(known.contains) ?? false) }
            case .custom(let id):
                matching = items.filter { $0.customAisleID == id }
            }
            return matching.isEmpty ? nil : (section, matching)
        }
    }
}
