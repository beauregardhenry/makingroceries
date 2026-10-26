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
                    ForEach($store.shops) { $shop in
                        TextField("Store name", text: $shop.name)
                    }
                    .onDelete { offsets in
                        offsets.map { store.shops[$0] }.forEach(store.deleteShop)
                    }
                    .onMove { store.shops.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Your stores")
                } footer: {
                    Text("Tap a name to rename it. Swipe to delete a store; its items stay on your list without a store.")
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
