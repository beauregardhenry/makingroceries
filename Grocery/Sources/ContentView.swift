import SwiftUI

struct ContentView: View {
    @Environment(GroceryStore.self) private var store
    @State private var showingAdd = false
    @Environment(\.colorScheme) private var systemScheme
    @State private var showingThemes = false
    @State private var showingShops = false
    @State private var showingUsual = false
    @State private var showingMeals = false
    @State private var showingTotals = false
    @State private var showingPantry = false
    @State private var showingBackup = false
    @State private var showingReceipt = false
    @State private var showingTrip = false
    @State private var showingPlanner = false
    @State private var detailItem: GroceryItem?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("shoppingMode") private var shoppingMode = false
    @State private var clearedBatch: ClearedBatch?
    @State private var pricingItem: GroceryItem?
    @State private var priceText = ""
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

    /// The chosen filter; falls back to "All" when the chosen store was deleted.
    private var filter: ShopFilter {
        let filter = ShopFilter(raw: selectedShopRaw)
        if case .shop(let id) = filter, !store.shops.contains(where: { $0.id == id }) { return .all }
        return filter
    }

    private var selectedShop: Binding<ShopFilter> {
        Binding(get: { filter }, set: { selectedShopRaw = $0.raw })
    }

    private func isVisible(_ item: GroceryItem) -> Bool {
        switch filter {
        case .all: true
        case .anyStore: item.shopID == nil
        case .shop(let id): item.shopID == id
        }
    }

    private var visibleItems: [GroceryItem] {
        store.items.filter(isVisible)
    }

    /// The store new items start in: the chosen one, otherwise none.
    private var newItemShopID: UUID? {
        if case .shop(let id) = filter { return id }
        return nil
    }

    private var navigationTitle: String {
        switch filter {
        case .all: "Groceries"
        case .anyStore: "Any Store"
        case .shop(let id): store.shopName(for: id) ?? "Groceries"
        }
    }

    /// The store whose aisle map applies, when one store is selected.
    private var mappedShop: Shop? {
        if case .shop(let id) = filter { return store.shop(for: id) }
        return nil
    }

    /// Sections follow the selected store's walking order, or the default order otherwise.
    private var sections: [(Aisle, [GroceryItem])] {
        (mappedShop?.orderedAisles ?? Aisle.allCases).compactMap { aisle in
            let items = visibleItems.filter { $0.aisle == aisle }
            return items.isEmpty ? nil : (aisle, items)
        }
    }

    /// How many aisles on screen have everything checked off, for the finished-an-aisle buzz.
    private var finishedAisles: Int {
        Dictionary(grouping: visibleItems, by: \.aisle).values.filter { $0.allSatisfy(\.isChecked) }.count
    }

    private var remainingCount: Int { visibleItems.filter { !$0.isChecked }.count }

    /// Changes whenever the Live Activity needs to be brought up to date.
    private var activityKey: String { "\(shoppingMode)|\(selectedShopRaw)|\(remainingCount)|\(visibleItems.count)" }

    private func syncShoppingActivity() {
        #if os(iOS)
        let next = displaySections.lazy.flatMap(\.items).first { !$0.isChecked }?.name
        let (remaining, total, name, active) = (remainingCount, visibleItems.count, navigationTitle, shoppingMode)
        Task { await ShoppingActivity.sync(storeName: name, remaining: remaining, total: total, next: next, active: active) }
        #endif
    }

    private struct DisplaySection: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let label: String?
        let items: [GroceryItem]
    }

    /// Normal view: by aisle. Shopping mode: what's still needed by aisle, then what's in the cart.
    private var displaySections: [DisplaySection] {
        let order = mappedShop?.orderedAisles ?? Aisle.allCases
        func make(_ aisle: Aisle, _ items: [GroceryItem]) -> DisplaySection {
            DisplaySection(id: aisle.rawValue, title: aisle.rawValue, symbol: aisle.symbol,
                           label: mappedShop?.label(for: aisle), items: items)
        }
        guard shoppingMode else { return sections.map { make($0.0, $0.1) } }
        var result = order.compactMap { aisle -> DisplaySection? in
            let items = visibleItems.filter { $0.aisle == aisle && !$0.isChecked }
            return items.isEmpty ? nil : make(aisle, items)
        }
        let cart = visibleItems.filter(\.isChecked)
        if !cart.isEmpty {
            result.append(DisplaySection(id: "cart", title: "In the cart", symbol: "cart.fill", label: nil, items: cart))
        }
        return result
    }

    /// The visible list as plain text, grouped by aisle in walking order, for sharing.
    private var shareText: String {
        var lines = [filter == .all ? "Grocery list" : "\(navigationTitle) list"]
        for (aisle, items) in sections {
            var header = aisle.rawValue
            if let label = mappedShop?.label(for: aisle) { header += " (\(label))" }
            lines += ["", header]
            for item in items {
                var line = "\(item.isChecked ? "☑" : "☐") \(item.name)"
                if item.quantity > 1 { line += " ×\(item.quantity)" }
                if filter == .all, let shop = store.shopName(for: item.shopID) { line += " (\(shop))" }
                lines.append(line)
            }
        }
        let totals = Totals(visibleItems)
        if totals.priced > 0 { lines += ["", "Total: \(Price.format(totals.sum))"] }
        return lines.joined(separator: "\n")
    }

    private func clearDone() {
        let removed = store.clearChecked(where: isVisible)
        guard !removed.isEmpty else { return }
        withAnimation { clearedBatch = ClearedBatch(items: removed) }
    }

    private func beginPricing(_ item: GroceryItem) {
        priceText = Price.editText(item.price)
        pricingItem = item
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(displaySections) { section in
                    Section {
                        ForEach(section.items) { item in
                            ItemRow(item: item, showShop: filter == .all, large: shoppingMode,
                                    onSetPrice: beginPricing, onEdit: { detailItem = $0 })
                        }
                        .onDelete { offsets in
                            offsets.map { section.items[$0] }.forEach(store.delete)
                        }
                    } header: {
                        HStack {
                            Label(section.title, systemImage: section.symbol)
                            Spacer()
                            if let label = section.label {
                                Text(label).textCase(nil).font(.subheadline.weight(.semibold))
                            }
                        }
                        .font(shoppingMode ? .headline : nil)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ShopBar(selection: selectedShop) { showingShops = true }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let batch = clearedBatch {
                        UndoBanner(count: batch.items.count) {
                            withAnimation {
                                store.restore(batch.items)
                                clearedBatch = nil
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TotalsBar(items: visibleItems) { showingTotals = true }
                    QuickAddBar(shopID: newItemShopID, inferShop: filter == .all)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
            .task(id: clearedBatch?.id) {
                guard let id = clearedBatch?.id else { return }
                try? await Task.sleep(for: .seconds(7))
                if clearedBatch?.id == id { withAnimation { clearedBatch = nil } }
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
                                           description: Text(filter == .all
                                                             ? "Tap + to add your first item."
                                                             : "Tap + to add something here."))
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear Done", action: clearDone)
                        .disabled(!visibleItems.contains(where: \.isChecked))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Usual & Buy Again", systemImage: "star") { showingUsual = true }
                        Button("Pantry Check", systemImage: "checklist") { showingPantry = true }
                        Button("Meals", systemImage: "fork.knife") { showingMeals = true }
                        Button("Meal Plan", systemImage: "calendar") { showingPlanner = true }
                        Button("Totals by Store", systemImage: "dollarsign.circle") { showingTotals = true }
                        Button("Plan the Trip", systemImage: "arrow.left.arrow.right") { showingTrip = true }
                        Button("Scan Receipt", systemImage: "receipt") { showingReceipt = true }
                        Divider()
                        Toggle(isOn: $shoppingMode) {
                            Label("Shopping Mode", systemImage: "textformat.size")
                        }
                        ShareLink(item: shareText) {
                            Label("Share List", systemImage: "square.and.arrow.up")
                        }
                        .disabled(visibleItems.isEmpty)
                        Button("Back Up & Restore", systemImage: "externaldrive") { showingBackup = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    Button("Color", systemImage: "paintpalette") { showingThemes = true }
                        .popover(isPresented: $showingThemes) { ThemePicker(selection: theme, custom: customColor, appearance: appearance) }
                    Button("Add", systemImage: "plus") { showingAdd = true }
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemView(shopID: newItemShopID) }
            .sheet(isPresented: $showingShops) { ManageShopsView() }
            .sheet(isPresented: $showingUsual) { UsualView(shopID: newItemShopID) }
            .sheet(isPresented: $showingMeals) { MealsView(shopID: newItemShopID, currentItems: visibleItems) }
            .sheet(isPresented: $showingTotals) { TotalsView() }
            .sheet(isPresented: $showingPantry) { PantryCheckView(shopID: newItemShopID) }
            .sheet(isPresented: $showingBackup) { BackupView() }
            .sheet(isPresented: $showingReceipt) { ReceiptView(shopID: newItemShopID) }
            .sheet(isPresented: $showingTrip) { TripPlanView() }
            .sheet(isPresented: $showingPlanner) { PlannerView(shopID: newItemShopID) }
            .sheet(item: $detailItem) { item in
                ItemDetailView(item: item, repeatDays: store.recurrence(for: item)?.everyDays ?? 0)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.reload()
                    Task { await ArrivalReminders.shared.refreshNearestStore(among: store.shops) }
                }
            }
            .modifier(ShoppingFeedback(finishedAisles: finishedAisles, key: activityKey, sync: syncShoppingActivity))
            .alert("Set Price", isPresented: Binding(get: { pricingItem != nil },
                                                     set: { if !$0 { pricingItem = nil } }),
                   presenting: pricingItem) { item in
                TextField("0.00", text: $priceText).keyboardType(.decimalPad)
                Button("Save") { store.setPrice(Price.parse(priceText), for: item) }
                Button("Remove Price", role: .destructive) { store.setPrice(nil, for: item) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Price of one \(item.name)")
            }
        }
        .preferredColorScheme(appearance.wrappedValue.scheme)
    }
}

struct ItemRow: View {
    @Environment(GroceryStore.self) private var store
    let item: GroceryItem
    var showShop = false
    /// Shopping mode: bigger text and tap targets.
    var large = false
    var onSetPrice: (GroceryItem) -> Void = { _ in }
    var onEdit: (GroceryItem) -> Void = { _ in }

    /// Second line: the store (when listing every store) and the unit price.
    private var detail: String? {
        var parts: [String] = []
        if showShop, let shop = store.shopName(for: item.shopID) { parts.append(shop) }
        if let price = item.price { parts.append(item.quantity > 1 ? "\(Price.format(price)) each" : Price.format(price)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var spokenSummary: String {
        var parts = [item.name]
        if item.quantity > 1 { parts.append("quantity \(item.quantity)") }
        if let shop = store.shopName(for: item.shopID), showShop { parts.append(shop) }
        if let line = item.lineTotal { parts.append(Price.format(line)) }
        if let note = item.note { parts.append(note) }
        parts.append(item.isChecked ? "bought" : "needed")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            withAnimation { store.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .font(large ? .title : .title3)
                if let photo = item.photo {
                    ItemThumbnail(name: photo, size: large ? 52 : 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(large ? .title3.weight(.medium) : .body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = item.note {
                        Text(note).font(.caption).italic().foregroundStyle(.secondary)
                    }
                    if !item.isChecked, let hint = store.priceHint(for: item) {
                        Text(hint).font(.caption).foregroundStyle(.green)
                    }
                }
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                        .font(large ? .title3 : .body)
                }
                if let line = item.lineTotal {
                    Text(Price.format(line)).monospacedDigit()
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                }
            }
            .padding(.vertical, large ? 8 : 0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: item.isChecked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityHint(item.isChecked ? "Double tap to put it back on the list" : "Double tap to mark it bought")
        .accessibilityAction(named: "Edit details") { onEdit(item) }
        .accessibilityAction(named: "Set price") { onSetPrice(item) }
        .accessibilityAction(named: "Delete") { store.delete(item) }
        .contextMenu {
            Button("Edit Details…", systemImage: "pencil") { onEdit(item) }
            Button("Set Price…", systemImage: "dollarsign.circle") { onSetPrice(item) }
            Button("Add to Usual", systemImage: "star") {
                store.addFavorite(name: item.name, quantity: item.quantity, aisle: item.aisle)
            }
            Menu("Move to Store", systemImage: "arrow.right.circle") {
                ForEach(store.shops) { shop in
                    Button(shop.name) { store.move(item, to: shop.id) }
                }
                Button("Any Store") { store.move(item, to: nil) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
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
    @State private var priceText = ""
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
                TextField("Price (optional)", text: $priceText).keyboardType(.decimalPad)
                Picker("Aisle", selection: $aisle) {
                    ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Picker("Store", selection: $shopID) {
                    Text("Any Store").tag(UUID?.none)
                    ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(name: name, quantity: quantity, aisle: aisle, shopID: shopID, price: Price.parse(priceText))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                store.add(name: product.name, quantity: quantity, aisle: product.aisle ?? aisle, shopID: shopID, price: Price.parse(priceText))
                dismiss()
            } else {
                lookupMessage = "No product found for \(code). Type the name instead."
            }
        } catch {
            lookupMessage = "Couldn't look up that barcode. Check your connection."
        }
    }
}

/// What Clear Done removed, kept briefly so it can be undone.
struct ClearedBatch: Identifiable {
    let id = UUID()
    let items: [ClearedItem]
}

struct UndoBanner: View {
    let count: Int
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Cleared \(count) item\(count == 1 ? "" : "s")")
            Spacer()
            Button("Undo", action: onUndo).fontWeight(.semibold)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }
}

/// The finished-an-aisle buzz, and keeping the lock screen Live Activity current.
private struct ShoppingFeedback: ViewModifier {
    let finishedAisles: Int
    let key: String
    let sync: () -> Void

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: finishedAisles) { old, new in new > old ? .success : nil }
            .onChange(of: key) { _, _ in sync() }
    }
}
