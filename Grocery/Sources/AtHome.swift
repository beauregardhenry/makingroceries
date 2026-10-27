import SwiftUI

/// What's in your kitchen and when to use it by.
struct AtHomeView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tracking = GroceryStore.tracksStock
    @State private var reminders = ExpiryReminders.enabled

    private func daysLeft(_ entry: StockEntry) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: entry.expires)).day ?? 0
    }

    private func color(_ days: Int) -> Color { days <= 1 ? .red : (days <= 3 ? .orange : .secondary) }

    private func text(_ days: Int) -> String {
        switch days {
        case ..<0: "Use now, \(-days) day\(days == -1 ? "" : "s") past"
        case 0: "Use today"
        case 1: "Use by tomorrow"
        default: "Use within \(days) days"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Track what I buy", isOn: $tracking)
                    Toggle("Remind me to use things", isOn: $reminders)
                        .disabled(!tracking)
                } footer: {
                    Text("When you check off food that spoils, like produce, dairy, meat and bread, it appears here with a rough use-by date. These are guides, not food-safety advice.")
                }

                if store.stock.isEmpty {
                    Section {
                        ContentUnavailableView("Nothing tracked yet", systemImage: "refrigerator",
                                               description: Text("Check off some groceries and they'll appear here."))
                    }
                } else {
                    Section("Use these first") {
                        ForEach(store.stockByExpiry()) { entry in
                            let days = daysLeft(entry)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    Text(text(days)).font(.caption).foregroundStyle(color(days))
                                }
                                Spacer()
                                Text("Bought \(entry.bought.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Used", systemImage: "checkmark") { store.useUp(entry, addBack: false) }.tint(.green)
                                Button("Buy Again", systemImage: "cart.badge.plus") { store.useUp(entry, addBack: true) }.tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Tossed", systemImage: "trash") { store.removeStock(entry.id) }.tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("At Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: tracking) { _, on in GroceryStore.tracksStock = on }
            .onChange(of: reminders) { _, on in
                ExpiryReminders.enabled = on
                Task {
                    if on { _ = await ExpiryReminders.requestPermission() }
                    await ExpiryReminders.reschedule(store.stock)
                }
            }
        }
    }
}
