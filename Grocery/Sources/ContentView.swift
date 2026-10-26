import SwiftUI

struct ContentView: View {
    @Environment(GroceryStore.self) private var store
    @State private var showingAdd = false
    @Environment(\.colorScheme) private var systemScheme
    @State private var showingThemes = false
    @State private var showingShops = false
    @AppStorage("selectedShop") private var selectedShopRaw = ""
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

    /// The chosen store, or nil for "All" (also when the chosen store was deleted).
    private var selectedShopID: UUID? {
        UUID(uuidString: selectedShopRaw).flatMap { id in store.shops.contains { $0.id == id } ? id : nil }
    }

    private var selectedShop: Binding<UUID?> {
        Binding(get: { selectedShopID }, set: { selectedShopRaw = $0?.uuidString ?? "" })
    }

    private var visibleItems: [GroceryItem] {
        guard let id = selectedShopID else { return store.items }
        return store.items.filter { $0.shopID == id }
    }

    private var navigationTitle: String {
        store.shopName(for: selectedShopID) ?? "Groceries"
    }

    private var sections: [(Aisle, [GroceryItem])] {
        Aisle.allCases.compactMap { aisle in
            let items = visibleItems.filter { $0.aisle == aisle }
            return items.isEmpty ? nil : (aisle, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { aisle, items in
                    Section {
                        ForEach(items) { item in
                            ItemRow(item: item, showShop: selectedShopID == nil)
                        }
                        .onDelete { offsets in
                            offsets.map { items[$0] }.forEach(store.delete)
                        }
                    } header: {
                        Label(aisle.rawValue, systemImage: aisle.symbol)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ShopBar(selection: selectedShop) { showingShops = true }
            }
            .scrollContentBackground(.hidden)
            .background {
                Color(.systemGroupedBackground)
                    .overlay(theme.wrappedValue.tint(custom: customColor.wrappedValue).opacity(tintOpacity))
                    .ignoresSafeArea()
            }
            .animation(.default, value: themeName + customHex)
            .overlay {
                if visibleItems.isEmpty {
                    ContentUnavailableView("Your list is empty", systemImage: "cart",
                                           description: Text(selectedShopID == nil
                                                             ? "Tap + to add your first item."
                                                             : "Tap + to add something for this store."))
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear Done") { store.clearChecked(shopID: selectedShopID) }
                        .disabled(!visibleItems.contains(where: \.isChecked))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Color", systemImage: "paintpalette") { showingThemes = true }
                        .popover(isPresented: $showingThemes) { ThemePicker(selection: theme, custom: customColor, appearance: appearance) }
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemView(shopID: selectedShopID) }
            .sheet(isPresented: $showingShops) { ManageShopsView() }
        }
        .preferredColorScheme(appearance.wrappedValue.scheme)
    }
}

struct ItemRow: View {
    @Environment(GroceryStore.self) private var store
    let item: GroceryItem
    var showShop = false

    var body: some View {
        Button {
            withAnimation { store.toggle(item) }
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if showShop, let shop = store.shopName(for: item.shopID) {
                        Text(shop).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to Store", systemImage: "arrow.right.circle") {
                ForEach(store.shops) { shop in
                    Button(shop.name) { store.move(item, to: shop.id) }
                }
                Button("No Store") { store.move(item, to: nil) }
            }
        }
    }
}

struct AddItemView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var aisle: Aisle = .produce
    @State private var shopID: UUID?
    @State private var showingScanner = false
    @State private var lookupMessage: String?
    @State private var isLookingUp = false

    init(shopID: UUID?) {
        _shopID = State(initialValue: shopID)
    }

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
                Picker("Store", selection: $shopID) {
                    Text("Any store").tag(UUID?.none)
                    ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(name: name, quantity: quantity, aisle: aisle, shopID: shopID)
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
                store.add(name: product.name, quantity: quantity, aisle: product.aisle ?? aisle, shopID: shopID)
                dismiss()
            } else {
                lookupMessage = "No product found for \(code). Type the name instead."
            }
        } catch {
            lookupMessage = "Couldn't look up that barcode. Check your connection."
        }
    }
}
