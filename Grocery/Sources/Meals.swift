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
    @State private var showingImport = false

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
            .sheet(isPresented: $showingImport) {
                RecipeImportView { id in path.append(id) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Meal", systemImage: "plus") { newMeal() }
                        Button("Save Current List as Meal", systemImage: "square.and.arrow.down") {
                            newMeal(from: currentItems)
                        }
                        .disabled(currentItems.isEmpty)
                        Button("Import Recipe…", systemImage: "doc.text.magnifyingglass") { showingImport = true }
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

/// Turns a recipe web page or pasted ingredient list into a meal.
struct RecipeImportView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void
    @State private var address = ""
    @State private var pasted = ""
    @State private var name = ""
    @State private var isFetching = false
    @State private var message: String?

    private var entries: [QuickAdd.Entry] { RecipeParser.fromText(pasted) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await fetch() }
                    } label: {
                        if isFetching { ProgressView() } else { Text("Get Ingredients from Page") }
                    }
                    .disabled(isFetching || address.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Recipe web address")
                } footer: {
                    Text("Works with most recipe sites. Only the address you enter is contacted.")
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    TextEditor(text: $pasted).frame(minHeight: 160)
                } header: {
                    Text("Ingredients, one per line")
                } footer: {
                    Text(entries.isEmpty ? "Paste a list, or fetch one above. Amounts like \"2 cups\" are dropped." : "\(entries.count) ingredient\(entries.count == 1 ? "" : "s") found.")
                }

                Section("Meal name") {
                    TextField("Name", text: $name)
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(entries.isEmpty)
                }
            }
        }
    }

    private func fetch() async {
        message = nil
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil else {
            message = "That doesn't look like a web address."
            return
        }
        isFetching = true
        defer { isFetching = false }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  let recipe = RecipeParser.fromHTML(html) else {
                message = "Couldn't find a recipe on that page. Copy the ingredients and paste them below instead."
                return
            }
            pasted = recipe.ingredients.map { $0.quantity > 1 ? "\($0.quantity) \($0.name)" : $0.name }.joined(separator: "\n")
            if name.isEmpty, let title = recipe.name { name = title }
        } catch {
            message = "Couldn't reach that page. Check your connection."
        }
    }

    private func create() {
        let meal = Meal(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported recipe" : name.trimmingCharacters(in: .whitespaces),
            ingredients: entries.map { MealIngredient(name: $0.name, quantity: $0.quantity, aisle: store.resolveAisle(for: $0.name)) }
        )
        store.meals.append(meal)
        dismiss()
        onCreated(meal.id)
    }
}
