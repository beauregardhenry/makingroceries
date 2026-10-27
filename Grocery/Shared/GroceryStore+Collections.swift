import Foundation

extension GroceryStore {
    // MARK: Usual items

    func addFavorite(name: String, quantity: Int = 1, aisle: Aisle? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !favorites.contains(where: { Self.same($0.name, trimmed) }) else { return }
        favorites.append(Favorite(name: trimmed, quantity: quantity, aisle: aisle ?? resolveAisle(for: trimmed)))
    }

    func addToList(_ favorite: Favorite, shopID: UUID?) {
        addOrBump(name: favorite.name, quantity: favorite.quantity, aisle: favorite.aisle,
                  shopID: shopID, inferShop: shopID == nil)
    }

    // MARK: Meals

    func addToList(_ meal: Meal, shopID: UUID?, scale: Double = 1) {
        for ingredient in meal.ingredients {
            let scaled = ingredient.scaled(by: scale)
            addOrBump(name: ingredient.name, quantity: scaled.quantity, aisle: ingredient.aisle,
                      shopID: shopID, inferShop: shopID == nil, note: scaled.note)
        }
    }

    /// A meal from ingredient lines (pasted, photographed or from a web page).
    func makeMeal(named name: String, fromLines lines: String) -> Meal {
        let ingredients = RecipeParser.fromText(lines).map { line in
            MealIngredient(name: line.name, quantity: line.quantity, aisle: resolveAisle(for: line.name),
                           amount: line.amount, unit: line.unit)
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Meal(name: trimmed.isEmpty ? "Imported recipe" : trimmed, ingredients: ingredients)
    }

    // MARK: Repeating items

    func recurrence(for item: GroceryItem) -> RecurringItem? {
        recurring.first { Self.same($0.name, item.name) }
    }

    /// Makes `item` come back every `days` days, or stops it when `days` is nil.
    func setRepeat(for item: GroceryItem, everyDays days: Int?) {
        recurring.removeAll { Self.same($0.name, item.name) }
        guard let days else { return }
        let next = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        recurring.append(RecurringItem(name: item.name, quantity: item.quantity, aisle: item.aisle,
                                       shopID: item.shopID, everyDays: days, nextDue: next))
    }

    /// Puts anything due back on the list and schedules its next return.
    func applyRecurring(now: Date = Date()) {
        var changed = false
        for i in recurring.indices where recurring[i].nextDue <= now {
            let entry = recurring[i]
            if !isOnList(entry.name) {
                add(name: entry.name, quantity: entry.quantity, aisle: entry.aisle, shopID: entry.shopID)
            }
            var next = entry.nextDue
            while next <= now { next = Calendar.current.date(byAdding: .day, value: entry.everyDays, to: next) ?? now.addingTimeInterval(86_400) }
            recurring[i].nextDue = next
            changed = true
        }
        _ = changed
    }

    // MARK: Stores

    /// Adds a store unless the name is blank or already taken (ignoring case).
    @discardableResult
    func addShop(named name: String) -> Shop? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !shops.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        let shop = Shop(name: trimmed)
        shops.append(shop)
        return shop
    }

    /// Items from a deleted store stay on the list, just without a store.
    func deleteShop(_ shop: Shop) {
        shops.removeAll { $0.id == shop.id }
        items = items.map { item in
            var item = item
            if item.shopID == shop.id { item.shopID = nil }
            return item
        }
    }

    func shop(for id: UUID?) -> Shop? {
        id.flatMap { id in shops.first { $0.id == id } }
    }

    func shopName(for id: UUID?) -> String? {
        id.flatMap { id in shops.first { $0.id == id }?.name }
    }

    // MARK: Backup

    func makeBackup() -> Backup {
        Backup(items: items, shops: shops, favorites: favorites, meals: meals, history: history, recurring: recurring, plan: plan, stock: stock, spending: spending)
    }

    func restore(_ backup: Backup) {
        items = backup.items
        shops = backup.shops
        favorites = backup.favorites
        meals = backup.meals
        history = backup.history
        recurring = backup.recurring
        plan = backup.plan ?? []
        stock = backup.stock ?? []
        spending = backup.spending ?? []
    }
}
