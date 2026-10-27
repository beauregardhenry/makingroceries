import SwiftUI

/// Which items the list screen shows.
enum ShopFilter: Equatable {
    case all
    /// Items that aren't tied to a particular store.
    case anyStore
    case shop(UUID)

    init(raw: String) {
        switch raw {
        case "any": self = .anyStore
        case let raw: self = UUID(uuidString: raw).map(ShopFilter.shop) ?? .all
        }
    }

    var raw: String {
        switch self {
        case .all: ""
        case .anyStore: "any"
        case .shop(let id): id.uuidString
        }
    }
}

/// Horizontal chips for choosing which store's list to show.
struct ShopBar: View {
    @Environment(GroceryStore.self) private var store
    @Binding var selection: ShopFilter
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: selection == .all) { selection = .all }
                chip("Any Store", isSelected: selection == .anyStore) { selection = .anyStore }
                ForEach(store.shops) { shop in
                    chip(shop.name.isEmpty ? "Unnamed store" : shop.name, isSelected: selection == .shop(shop.id)) {
                        selection = .shop(shop.id)
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

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Text(title)
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
                    ForEach(store.shops) { shop in
                        NavigationLink {
                            ShopMapView(shopID: shop.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shop.name.isEmpty ? "Unnamed store" : shop.name)
                                if shop.orderedAisles != Aisle.allCases || !shop.aisleLabels.isEmpty {
                                    Text("Custom aisle map").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { store.shops[$0] }.forEach(store.deleteShop)
                    }
                    .onMove { store.shops.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Your stores")
                } footer: {
                    Text("Tap a store to rename it and set its aisle order. Swipe to delete a store; its items stay on your list without a store.")
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
                Section("Name") {
                    TextField("Store name", text: $store.shops[i].name)
                }

                Section {
                    ForEach(store.shops[i].orderedAisles) { aisle in
                        HStack {
                            Label(aisle.rawValue, systemImage: aisle.symbol)
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
                        store.shops[i].aisleOrder = Aisle.allCases
                        store.shops[i].aisleLabels = [:]
                    }
                    .disabled(store.shops[i].aisleOrder == Aisle.allCases && store.shops[i].aisleLabels.isEmpty)
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
