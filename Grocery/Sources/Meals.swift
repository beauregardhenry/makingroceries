import SwiftUI

/// Saved meals: add every ingredient to the list in one tap.
struct MealsView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The store currently selected, if any; nil lets history pick.
    let shopID: UUID?
    /// What's on screen now, so it can be saved as a meal.
    let currentItems: [GroceryItem]
    @State private var path: [UUID] = []

    private func newMeal(from items: [GroceryItem] = []) {
        let meal = Meal(name: "New meal", ingredients: items.map {
            MealIngredient(name: $0.name, quantity: $0.quantity, aisle: $0.aisle)
        })
        store.meals.append(meal)
        path.append(meal.id)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.meals.isEmpty {
                    Section {
                        Text("No meals yet. Tap + to create one, or save what's on your list now as a meal.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.meals) { meal in
                    NavigationLink(value: meal.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                                Text("\(meal.ingredients.count) ingredient\(meal.ingredients.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                store.addToList(meal, shopID: shopID)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(meal.ingredients.isEmpty)
                        }
                    }
                }
                .onDelete { store.meals.remove(atOffsets: $0) }
            }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in MealEditorView(mealID: id, shopID: shopID) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Meal", systemImage: "plus") { newMeal() }
                        Button("Save Current List as Meal", systemImage: "square.and.arrow.down") {
                            newMeal(from: currentItems)
                        }
                        .disabled(currentItems.isEmpty)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct MealEditorView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealID: UUID
    let shopID: UUID?
    @State private var newText = ""

    var body: some View {
        @Bindable var store = store
        if let i = store.meals.firstIndex(where: { $0.id == mealID }) {
            List {
                Section("Name") {
                    TextField("Meal name", text: $store.meals[i].name)
                }

                Section {
                    ForEach($store.meals[i].ingredients) { $ingredient in
                        HStack {
                            Image(systemName: ingredient.aisle.symbol).foregroundStyle(.secondary).frame(width: 24)
                            TextField("Ingredient", text: $ingredient.name)
                            Stepper("Quantity \(ingredient.quantity)", value: $ingredient.quantity, in: 1...99)
                                .labelsHidden()
                            Text("×\(ingredient.quantity)").foregroundStyle(.secondary).monospacedDigit()
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    .onDelete { store.meals[i].ingredients.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add ingredients: rice, 2 chicken, broccoli", text: $newText)
                            .submitLabel(.done)
                            .onSubmit { addIngredients(to: i) }
                        Button("Add") { addIngredients(to: i) }
                            .disabled(QuickAdd.parse(newText).isEmpty)
                    }
                } header: {
                    Text("Ingredients")
                }

                Section {
                    Button("Add All to List", systemImage: "cart.badge.plus") {
                        store.addToList(store.meals[i], shopID: shopID)
                        dismiss()
                    }
                    .disabled(store.meals[i].ingredients.isEmpty)
                }
            }
            .navigationTitle(store.meals[i].name.isEmpty ? "Meal" : store.meals[i].name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Meal not found", systemImage: "fork.knife")
        }
    }

    private func addIngredients(to i: Int) {
        for entry in QuickAdd.parse(newText) {
            store.meals[i].ingredients.append(
                MealIngredient(name: entry.name, quantity: entry.quantity, aisle: store.resolveAisle(for: entry.name))
            )
        }
        newText = ""
    }
}
