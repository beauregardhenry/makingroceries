import SwiftUI

struct ContentView: View {
    @Environment(GroceryStore.self) private var store
    @State private var showingAdd = false

    private var sections: [(Aisle, [GroceryItem])] {
        Aisle.allCases.compactMap { aisle in
            let items = store.items.filter { $0.aisle == aisle }
            return items.isEmpty ? nil : (aisle, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { aisle, items in
                    Section {
                        ForEach(items) { item in
                            ItemRow(item: item)
                        }
                        .onDelete { offsets in
                            offsets.map { items[$0] }.forEach(store.delete)
                        }
                    } header: {
                        Label(aisle.rawValue, systemImage: aisle.symbol)
                    }
                }
            }
            .overlay {
                if store.items.isEmpty {
                    ContentUnavailableView("Your list is empty", systemImage: "cart",
                                           description: Text("Tap + to add your first item."))
                }
            }
            .navigationTitle("Groceries")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear Done", action: store.clearChecked)
                        .disabled(!store.items.contains(where: \.isChecked))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemView() }
        }
    }
}

struct ItemRow: View {
    @Environment(GroceryStore.self) private var store
    let item: GroceryItem

    var body: some View {
        Button {
            withAnimation { store.toggle(item) }
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .imageScale(.large)
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AddItemView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var aisle: Aisle = .produce

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                Picker("Aisle", selection: $aisle) {
                    ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(name: name, quantity: quantity, aisle: aisle)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
