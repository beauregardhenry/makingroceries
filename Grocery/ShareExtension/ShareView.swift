import SwiftUI

struct ShareView: View {
    let readInput: () async -> SharedInput
    let close: () -> Void

    private enum Phase { case loading, ready, failed(String) }

    @State private var store = GroceryStore()
    @State private var phase: Phase = .loading
    @State private var name = ""
    @State private var ingredients = ""
    @State private var done: String?

    private var found: Int { RecipeParser.fromText(ingredients).count }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) { ProgressView(); Text("Reading the recipe…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("No recipe found", systemImage: "fork.knife")
                    } description: {
                        Text(message)
                    }
                case .ready:
                    form
                }
            }
            .navigationTitle("Makin' Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
            }
        }
        .task { await load() }
    }

    private var form: some View {
        Form {
            Section("Meal name") {
                TextField("Name", text: $name)
            }
            Section {
                TextEditor(text: $ingredients).frame(minHeight: 200)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("\(found) ingredient\(found == 1 ? "" : "s"). Edit anything that looks wrong.")
            }
            Section {
                Button("Save as Meal", systemImage: "square.and.arrow.down") { save(addToList: false) }
                Button("Save and Add to List", systemImage: "cart.badge.plus") { save(addToList: true) }
            } footer: {
                if let done { Text(done).foregroundStyle(.green) }
            }
            .disabled(found == 0 || done != nil)
        }
    }

    private func load() async {
        switch await readInput() {
        case .url(let url):
            switch await RecipeFetcher.fetch(url) {
            case .found(let recipe):
                name = recipe.name ?? ""
                ingredients = recipe.lines.joined(separator: "\n")
                phase = .ready
            case .noRecipe:
                phase = .failed("This page doesn't share its ingredients in a form the app can read. Copy the ingredients, then use Meals → Import Recipe in the app.")
            case .unreachable, .badAddress:
                phase = .failed("Couldn't open that page. Check your connection.")
            }
        case .text(let text):
            ingredients = RecipeParser.ingredientSection(of: text.split(whereSeparator: \.isNewline).map(String.init)).joined(separator: "\n")
            phase = RecipeParser.fromText(ingredients).isEmpty ? .failed("I couldn't find ingredients in that text.") : .ready
        case .none:
            phase = .failed("There was nothing to read. Share a recipe page from Safari.")
        }
    }

    private func save(addToList: Bool) {
        let meal = store.makeMeal(named: name, fromLines: ingredients)
        store.meals.append(meal)
        if addToList { store.addToList(meal, shopID: nil) }
        done = addToList ? "Saved and added to your list." : "Saved to Meals."
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            close()
        }
    }
}
