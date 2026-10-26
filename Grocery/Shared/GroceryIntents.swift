import AppIntents
import Foundation

struct ShopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Store"
    static let defaultQuery = ShopQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ShopQuery: EntityStringQuery {
    private func all() -> [ShopEntity] {
        GroceryStore().shops.map { ShopEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [UUID]) async throws -> [ShopEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ShopEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [ShopEntity] { all() }
}

struct AddItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Grocery List"
    static let description = IntentDescription("Adds items to your grocery list. Separate several with commas.")

    @Parameter(title: "Items", requestValueDialog: "What would you like to add?")
    var items: String

    @Parameter(title: "Store")
    var shop: ShopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$items) to \(\.$shop)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let entries = QuickAdd.parse(items)
        guard !entries.isEmpty else { return .result(dialog: "I didn't catch an item to add.") }
        let store = GroceryStore()
        for entry in entries {
            store.addOrBump(name: entry.name, quantity: entry.quantity, shopID: shop?.id, inferShop: shop == nil)
        }
        let names = entries.map(\.name).formatted(.list(type: .and))
        return .result(dialog: "Added \(names).")
    }
}

struct ReadListIntent: AppIntent {
    static let title: LocalizedStringResource = "Read My Grocery List"
    static let description = IntentDescription("Reads out what's still on your grocery list.")

    @Parameter(title: "Store")
    var shop: ShopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Read the list for \(\.$shop)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = GroceryStore().widgetItems(shopID: shop?.id)
        guard !items.isEmpty else { return .result(dialog: "Your list is empty.") }
        let spoken = items.prefix(12).map { $0.quantity > 1 ? "\($0.quantity) \($0.name)" : $0.name }
        let more = items.count > 12 ? " and \(items.count - 12) more" : ""
        return .result(dialog: "You need \(spoken.formatted(.list(type: .and)))\(more).")
    }
}

/// Used by the widget's check-off buttons.
struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Off Item"
    static let isDiscoverable = false

    @Parameter(title: "Item")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        let store = GroceryStore()
        if let item = store.items.first(where: { $0.id.uuidString == itemID }) { store.toggle(item) }
        return .result()
    }
}
