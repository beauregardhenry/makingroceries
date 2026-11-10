import SwiftUI

/// Horizontal chips for choosing which store's list to show.
struct ShopBar: View {
    @Environment(GroceryStore.self) private var store
    @Binding var selection: ShopFilter
    let onManage: () -> Void
    @AppStorage(ChipOrder.key) private var travelPosition = ChipOrder.last
    @AppStorage(ChipOrder.clothingKey) private var clothingPosition = ChipOrder.clothingLast

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: selection == .all) { selection = .all }
                ForEach(ChipOrder.entries(shops: store.shops, travelPosition: travelPosition, clothingPosition: clothingPosition), id: \.self) { entry in
                    switch entry {
                    case .travel:
                        chip("Travel", symbol: "airplane", isSelected: selection == .travel) { selection = .travel }
                    case .clothing:
                        chip("Clothing", symbol: "tshirt.fill", isSelected: selection == .clothing) { selection = .clothing }
                    case .shop(let id):
                        if let shop = store.shop(for: id) {
                            chip(shop.name.isEmpty ? "Unnamed store" : shop.name, isSelected: selection == .shop(id)) {
                                selection = .shop(id)
                            }
                        }
                    }
                }
                Button(action: onManage) {
                    Image(systemName: "slider.horizontal.3")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.fill.tertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage stores")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, symbol: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Label { Text(title) } icon: { if let symbol { Image(systemName: symbol) } }
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ManageShopsView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""
    @AppStorage(ChipOrder.key) private var travelPosition = ChipOrder.last
    @AppStorage(ChipOrder.clothingKey) private var clothingPosition = ChipOrder.clothingLast

    private var availablePresets: [String] {
        Shop.presetNames.filter { preset in
            !store.shops.contains { $0.name.caseInsensitiveCompare(preset) == .orderedSame }
        }
    }

    private func addCustom() {
        if store.addShop(named: customName) != nil { customName = "" }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    let entries = ChipOrder.entries(shops: store.shops, travelPosition: travelPosition, clothingPosition: clothingPosition)
                    ForEach(entries, id: \.self) { entry in
                        switch entry {
                        case .travel:
                            Label("Travel", systemImage: "airplane")
                                .deleteDisabled(true)
                        case .clothing:
                            Label("Clothing", systemImage: "tshirt.fill")
                                .deleteDisabled(true)
                        case .shop(let id):
                            if let shop = store.shop(for: id) {
                                NavigationLink {
                                    ShopMapView(shopID: id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shop.name.isEmpty ? "Unnamed store" : shop.name)
                                        if shop.orderedAisles != shop.defaultOrder || !shop.aisleLabels.isEmpty {
                                            Text("Custom aisle map").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            if case .shop(let id) = entries[offset], let shop = store.shop(for: id) { store.deleteShop(shop) }
                        }
                    }
                    .onMove { offsets, destination in
                        var arranged = entries
                        arranged.move(fromOffsets: offsets, toOffset: destination)
                        store.shops = ChipOrder.shops(store.shops, arrangedBy: arranged)
                        travelPosition = ChipOrder.position(of: arranged)
                        clothingPosition = ChipOrder.position(of: arranged, chip: .clothing)
                    }
                } header: {
                    Text("Your stores")
                } footer: {
                    Text("Drag to put the stores, Travel and Clothing in the order you want them on the list screen. Tap a store to rename it and set its aisle order. Swipe to delete a store; its items stay on your list without a store.")
                }

                Section {
                    Toggle("Switch to a store's list when I arrive", isOn: Binding(
                        get: { ArrivalReminders.autoSwitch },
                        set: { ArrivalReminders.autoSwitch = $0 }
                    ))
                } footer: {
                    Text("Needs a saved location for the store (open a store below). Picking another store by hand stays until you arrive somewhere new.")
                }

                Section("Add your own") {
                    HStack {
                        TextField("Custom store name", text: $customName)
                            .submitLabel(.done)
                            .onSubmit(addCustom)
                        Button("Add", action: addCustom)
                            .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !availablePresets.isEmpty {
                    Section("Popular stores") {
                        ForEach(availablePresets, id: \.self) { name in
                            Button {
                                store.addShop(named: name)
                            } label: {
                                Label(name, systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Edit one store: its name, the order its aisles are walked in, and optional aisle labels.
struct ShopMapView: View {
    @Environment(GroceryStore.self) private var store
    let shopID: UUID
    @State private var locationMessage: String?

    var body: some View {
        @Bindable var store = store
        if let i = store.shops.firstIndex(where: { $0.id == shopID }) {
            List {
                Section {
                    TextField("Store name", text: $store.shops[i].name)
                    Picker("Type", selection: Binding(
                        get: { store.shops[i].kind ?? .grocery },
                        set: { kind in
                            store.shops[i].kind = kind == .grocery ? nil : kind
                            store.shops[i].aisleOrder = kind.defaultOrder
                        }
                    )) {
                        ForEach(ShopKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text("General and hardware stores put tools, garden, electronics and other non-food aisles in the order you'd walk them. Changing the type resets the aisle order.")
                }

                Section {
                    ForEach(store.shops[i].orderedAisles) { aisle in
                        HStack(spacing: 12) {
                            AisleBadge(aisle: aisle, size: 28)
                            Text(aisle.rawValue)
                            Spacer()
                            TextField("Aisle", text: labelBinding(index: i, aisle: aisle))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 120)
                        }
                    }
                    .onMove { offsets, destination in
                        var order = store.shops[i].orderedAisles
                        order.move(fromOffsets: offsets, toOffset: destination)
                        store.shops[i].aisleOrder = order
                        // Setting the order by hand means you don't want it changed underneath you.
                        store.shops[i].learnRoute = false
                    }
                } header: {
                    Text("Aisle order")
                } footer: {
                    Text("Drag the handles to match the route you walk in this store. The list sorts this way when the store is selected. The optional label on the right, like \"Aisle 7\", shows in each section header.")
                }

                Section {
                    Toggle("Learn my route", isOn: Binding(
                        get: { store.shops[i].learnRoute != false },
                        set: { store.shops[i].learnRoute = $0 }
                    ))
                } footer: {
                    let trips = store.tripCount(for: store.shops[i])
                    Text(store.shops[i].learnRoute == false
                         ? "Off, because you set the order by hand. Turn it on and the app will adjust it as you shop."
                         : "As you check things off here, the app learns the order you walk the aisles in and updates this list after a few trips. Trips learned from so far: \(trips).")
                }

                Section {
                    Button {
                        Task { await useCurrentLocation(index: i) }
                    } label: {
                        Label(store.shops[i].hasLocation ? "Update Location to Here" : "Use My Current Location",
                              systemImage: "location")
                    }
                    if store.shops[i].hasLocation {
                        Toggle("Remind me when I arrive", isOn: Binding(
                            get: { store.shops[i].remindOnArrival == true },
                            set: { on in
                                store.shops[i].remindOnArrival = on
                                if on { Task { await ArrivalReminders.shared.requestPermissions() } }
                            }
                        ))
                        Button("Clear Location", role: .destructive) {
                            store.shops[i].latitude = nil
                            store.shops[i].longitude = nil
                            store.shops[i].remindOnArrival = nil
                        }
                    }
                    if let locationMessage {
                        Text(locationMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Arrival reminder")
                } footer: {
                    Text("Tap while you're at the store. When you arrive later, you get a notification listing what's on this store's list. For this to work with the app closed, choose \"Always\" for location. Your location never leaves this device.")
                }

                Section {
                    Button("Reset to Default Order", role: .destructive) {
                        store.shops[i].aisleOrder = store.shops[i].defaultOrder
                        store.shops[i].aisleLabels = [:]
                    }
                    .disabled(store.shops[i].aisleOrder == store.shops[i].defaultOrder && store.shops[i].aisleLabels.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(store.shops[i].name.isEmpty ? "Store" : store.shops[i].name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Store not found", systemImage: "storefront")
        }
    }

    private func useCurrentLocation(index i: Int) async {
        locationMessage = nil
        guard let coordinate = await ArrivalReminders.shared.currentLocation() else {
            locationMessage = "Couldn't get your location. Allow location access for Makin' Groceries in Settings, then try again."
            return
        }
        guard store.shops.indices.contains(i) else { return }
        store.shops[i].latitude = coordinate.latitude
        store.shops[i].longitude = coordinate.longitude
        locationMessage = "Location saved."
    }

    private func labelBinding(index i: Int, aisle: Aisle) -> Binding<String> {
        Binding(
            get: { store.shops[i].aisleLabels[aisle.rawValue] ?? "" },
            set: { store.shops[i].aisleLabels[aisle.rawValue] = $0 }
        )
    }
}
