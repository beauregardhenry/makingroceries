import SwiftUI

enum Price {
    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    /// Accepts "3", "3.49", "$3,49"; nil for anything that isn't a non-negative number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    /// Text for an editing field: no currency symbol, no trailing zeros noise.
    static func editText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}

extension GroceryItem {
    /// Price of the whole quantity.
    var lineTotal: Double? { price.map { $0 * Double(quantity) } }
}

struct Totals {
    var sum = 0.0
    var priced = 0
    var count = 0

    init(_ items: [GroceryItem]) {
        for item in items {
            count += 1
            if let line = item.lineTotal {
                sum += line
                priced += 1
            }
        }
    }
}

/// "Total $24.50" for what's on screen; tapping opens the per-store breakdown.
struct TotalsBar: View {
    let items: [GroceryItem]
    let onTap: () -> Void

    var body: some View {
        let totals = Totals(items)
        if totals.priced > 0 {
            Button(action: onTap) {
                HStack {
                    Text("Total").foregroundStyle(.secondary)
                    Text(Price.format(totals.sum)).font(.headline).monospacedDigit()
                    Spacer()
                    Text(totals.priced == totals.count ? "All priced" : "\(totals.priced) of \(totals.count) priced")
                        .font(.footnote).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows totals by store")
        }
    }
}

struct TotalsView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("By store") {
                    ForEach(store.shops) { shop in
                        row(shop.name, items: store.items.filter { $0.shopID == shop.id })
                    }
                    row("Any Store", items: store.items.filter { $0.shopID == nil })
                }
                Section {
                    let all = Totals(store.items)
                    HStack {
                        Text("Everything").font(.headline)
                        Spacer()
                        Text(Price.format(all.sum)).font(.headline).monospacedDigit()
                    }
                } footer: {
                    Text("Totals count only items that have a price. Long-press an item to set one.")
                }
            }
            .navigationTitle("Totals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func row(_ title: String, items: [GroceryItem]) -> some View {
        let totals = Totals(items)
        if totals.count > 0 {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("\(totals.count) item\(totals.count == 1 ? "" : "s"), \(totals.priced) priced")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Price.format(totals.sum)).monospacedDigit()
            }
        }
    }
}
