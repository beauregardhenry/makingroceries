import SwiftUI

/// Sections you name yourself, like "Aisle 5" or "Baking", beside the built-in categories.
struct CustomAislesView: View {
    @Environment(GroceryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NamedListEditor(
            title: "Custom Aisles", placeholder: "Aisle name (Aisle 5, Baking, Bulk…)", header: "Your aisles",
            footer: "Categories like Produce and Dairy stay. Pick one of these aisles on an item and it is listed under that name instead. Set where each one falls in a store under Stores. Deleting an aisle puts its items back under their category.",
            items: $store.customAisles, name: \.name,
            add: { store.addCustomAisle(named: $0) != nil }, delete: store.deleteCustomAisle)
    }
}
