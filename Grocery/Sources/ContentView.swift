import SwiftUI

struct ContentView: View {
    @Environment(GroceryStore.self) private var store
    @State private var showingAdd = false
    @Environment(\.colorScheme) private var systemScheme
    @State private var showingThemes = false
    @AppStorage("theme") private var themeName = Theme.grey.rawValue
    @AppStorage("appearance") private var appearanceName = Appearance.system.rawValue
    @AppStorage("customColor") private var customHex = "34C759"

    private var theme: Binding<Theme> {
        Binding(get: { Theme(rawValue: themeName) ?? .grey }, set: { themeName = $0.rawValue })
    }

    private var appearance: Binding<Appearance> {
        Binding(get: { Appearance(rawValue: appearanceName) ?? .system }, set: { appearanceName = $0.rawValue })
    }

    private var customColor: Binding<Color> {
        Binding(get: { Color(hex: customHex) },
                set: { customHex = $0.hex; themeName = Theme.custom.rawValue })
    }

    /// The tint is softer on dark backgrounds, where the same strength turns muddy.
    private var tintOpacity: Double {
        let dark = appearance.wrappedValue.scheme.map { $0 == .dark } ?? (systemScheme == .dark)
        return dark ? 0.12 : 0.22
    }

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
            .scrollContentBackground(.hidden)
            .background {
                Color(.systemGroupedBackground)
                    .overlay(theme.wrappedValue.tint(custom: customColor.wrappedValue).opacity(tintOpacity))
                    .ignoresSafeArea()
            }
            .animation(.default, value: themeName + customHex)
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Color", systemImage: "paintpalette") { showingThemes = true }
                        .popover(isPresented: $showingThemes) { ThemePicker(selection: theme, custom: customColor, appearance: appearance) }
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemView() }
        }
        .preferredColorScheme(appearance.wrappedValue.scheme)
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
    @State private var showingScanner = false
    @State private var lookupMessage: String?
    @State private var isLookingUp = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                Button("Scan Barcode", systemImage: "barcode.viewfinder") { showingScanner = true }
                if isLookingUp {
                    HStack { ProgressView(); Text("Looking up product…").foregroundStyle(.secondary) }
                } else if let lookupMessage {
                    Text(lookupMessage).font(.footnote).foregroundStyle(.secondary)
                }
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
        .sheet(isPresented: $showingScanner) {
            ScanSheet { code in Task { await lookUp(code) } }
        }
    }

    private func lookUp(_ code: String) async {
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            if let product = try await ProductLookup.product(for: code) {
                store.add(name: product.name, quantity: quantity, aisle: product.aisle ?? aisle)
                dismiss()
            } else {
                lookupMessage = "No product found for \(code). Type the name instead."
            }
        } catch {
            lookupMessage = "Couldn't look up that barcode. Check your connection."
        }
    }
}
