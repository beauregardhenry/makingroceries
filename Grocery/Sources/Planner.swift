import SwiftUI

/// Plan which meals you'll cook on which days, then put all their ingredients on the list at once.
struct PlannerView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The store currently selected, if any; nil lets history pick.
    let shopID: UUID?
    @State private var shopForDays = 7
    @State private var message: String?

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var pendingCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: shopForDays, to: start) ?? start
        return store.upcomingPlan().filter { $0.day < end && $0.onList != true }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if store.meals.isEmpty {
                    Section {
                        Text("Add some meals first (Meals in the menu), then plan them here.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Shopping for", selection: $shopForDays) {
                        Text("3 days").tag(3)
                        Text("5 days").tag(5)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                    }
                    Button {
                        let n = store.addPlannedToList(days: shopForDays, shopID: shopID)
                        message = n == 0 ? "Nothing new to add." : "Added \(n) meal\(n == 1 ? "" : "s") to your list."
                    } label: {
                        Label(pendingCount == 0 ? "Add Planned Meals to List" : "Add \(pendingCount) Planned Meal\(pendingCount == 1 ? "" : "s") to List",
                              systemImage: "cart.badge.plus")
                    }
                    .disabled(pendingCount == 0)
                } footer: {
                    Text(message ?? "Adds the ingredients of everything planned in that time. A meal is only added once.")
                }

                ForEach(days, id: \.self) { day in
                    Section {
                        ForEach(store.planned(on: day)) { entry in
                            if let meal = store.meals.first(where: { $0.id == entry.mealID }) {
                                HStack {
                                    Text(meal.name)
                                    Spacer()
                                    if entry.onList == true {
                                        Label("On list", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let entries = store.planned(on: day)
                            offsets.map { entries[$0].id }.forEach(store.removePlan)
                        }
                        Menu {
                            ForEach(store.meals) { meal in
                                Button(meal.name) { store.addPlan(meal, on: day) }
                            }
                        } label: {
                            Label("Add a meal", systemImage: "plus.circle")
                        }
                        .disabled(store.meals.isEmpty)
                    } header: {
                        Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                    }
                }
            }
            .navigationTitle("Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: shopForDays) { _, _ in message = nil }
        }
    }
}
