import Foundation
import Observation

enum Aisle: String, CaseIterable, Codable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy & Eggs"
    case meat = "Meat & Seafood"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case drinks = "Drinks"
    case household = "Household"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .produce: "carrot"
        case .dairy: "cup.and.saucer"
        case .meat: "fish"
        case .bakery: "birthday.cake"
        case .pantry: "takeoutbag.and.cup.and.straw"
        case .frozen: "snowflake"
        case .drinks: "waterbottle"
        case .household: "sparkles"
        case .other: "cart"
        }
    }
}

struct GroceryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Int = 1
    var aisle: Aisle = .other
    var isChecked = false
}

@Observable
final class GroceryStore {
    var items: [GroceryItem] = [] {
        didSet { save() }
    }

    private let url = URL.documentsDirectory.appending(path: "grocery.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([GroceryItem].self, from: data) {
            items = decoded
        } else {
            items = [
                GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
                GroceryItem(name: "Milk", aisle: .dairy),
                GroceryItem(name: "Sourdough", aisle: .bakery),
            ]
        }
    }

    func add(name: String, quantity: Int, aisle: Aisle) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(GroceryItem(name: trimmed, quantity: quantity, aisle: aisle))
    }

    func toggle(_ item: GroceryItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].isChecked.toggle()
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearChecked() {
        items.removeAll(where: \.isChecked)
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }
}
