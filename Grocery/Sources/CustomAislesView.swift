import SwiftUI

/// Sections you name yourself, like "Aisle 5" or "Baking", beside the built-in categories.
struct CustomAislesView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    private func add() {
        if store.addCustomAisle(named: newName) != nil { newName = "" }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Aisle name (Aisle 5, Baking, Bulk…)", text: $newName).textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach($store.customAisles) { $aisle in
                        TextField("Name", text: $aisle.name).textInputAutocapitalization(.words)
                    }
                    .onDelete { offsets in offsets.map { store.customAisles[$0].id }.forEach(store.deleteCustomAisle) }
                    .onMove { store.customAisles.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Your aisles")
                } footer: {
                    Text("Categories like Produce and Dairy stay. Pick one of these aisles on an item and it is listed under that name instead. Set where each one falls in a store under Stores. Deleting an aisle puts its items back under their category.")
                }
            }
            .navigationTitle("Custom Aisles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
