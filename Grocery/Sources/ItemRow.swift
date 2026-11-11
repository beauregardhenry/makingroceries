import SwiftUI

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
        if let price = item.price, item.quantity > 1 { parts.append("\(Price.format(price)) each") }
        if let unit = item.unitPriceText { parts.append(unit) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var spokenSummary: String {
        var parts = [item.name]
        if item.quantity > 1 { parts.append("quantity \(item.quantity)") }
        if let shop = store.shopName(for: item.shopID), showShop { parts.append(shop) }
        if let line = item.lineTotal { parts.append(Price.format(line)) }
        if let note = item.note { parts.append(note) }
        if let warning = item.warning { parts.append("Warning: \(warning)") }
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
                    .font(large ? .largeTitle : .title3)
                if let photo = item.photo {
                    ItemThumbnail(name: photo, size: large ? 52 : 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(large ? .title2.weight(.medium) : .body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if !large, let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = item.note {
                        Text(note).font(large ? .subheadline : .caption).italic().foregroundStyle(.secondary)
                    }
                    if let warning = item.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                    }
                    if !large, !item.isChecked, let hint = store.priceHint(for: item) {
                        Text(hint).font(.caption).foregroundStyle(Color.positive)
                    }
                }
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                        .font(large ? .title2.weight(.semibold) : .body)
                }
                if !large, let line = item.lineTotal {
                    Text(Price.format(line)).monospacedDigit()
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                }
            }
            .padding(.vertical, large ? 10 : 0)
            // A plain button only reacts to its text and icons; make the blank middle of the row tappable too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: item.isChecked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityIdentifier("item-\(item.name)")
        .accessibilityHint(item.isChecked ? "Double tap to put it back on the list" : "Double tap to mark it bought")
        .accessibilityAction(named: "Edit details") { onEdit(item) }
        .accessibilityAction(named: "Set price") { onSetPrice(item) }
        .accessibilityAction(named: "Delete") { store.delete(item) }
        .contextMenu {
            if item.list == .registry {
                ForEach(Array(RegistryInfo.lines(for: item).enumerated()), id: \.offset) { index, line in
                    Button(line, systemImage: index == 0 ? "calendar" : "gift") {}.disabled(true)
                }
                Divider()
            }
            if item.list == .clothing {
                // When it was added and its size, shown only here and never on the row.
                ForEach(Array(ClothingInfo.lines(for: item).enumerated()), id: \.offset) { index, line in
                    Button(line, systemImage: index == 0 ? "calendar" : "ruler") {}.disabled(true)
                }
                Divider()
            }
            Button("Edit Details…", systemImage: "pencil") { onEdit(item) }
            Button("Set Price…", systemImage: "dollarsign.circle") { onSetPrice(item) }
            Button("Add to Usual", systemImage: "star") {
                store.addFavorite(name: item.name, quantity: item.quantity, aisle: item.aisle)
            }
            if item.list == .registry {
                Menu("Move to Person", systemImage: "gift") {
                    ForEach(store.registryPeople) { person in
                        Button(person.name) { store.move(item, toGiftFor: person.id) }
                    }
                    Button("Not assigned yet") { store.move(item, toGiftFor: nil) }
                }
            } else if item.list == .clothing {
                Menu("Move to Person", systemImage: "person.crop.circle") {
                    ForEach(store.people) { person in
                        Button(person.name) { store.move(item, toPerson: person.id) }
                    }
                    Button("No one yet") { store.move(item, toPerson: nil) }
                }
            } else {
                Menu("Move to Store", systemImage: "arrow.right.circle") {
                    ForEach(store.shops) { shop in
                        Button(shop.name) { store.move(item, to: shop.id) }
                    }
                    Button(Shop.noStoreName) { store.move(item, to: nil) }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
        }
    }
}
