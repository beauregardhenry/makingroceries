import Foundation

/// A saved meal measured against what's at home: what you already have, what you'd need to buy,
/// and which of the things you have should be used soon.
struct MealMatch: Identifiable, Equatable {
    var meal: Meal
    var have: [String]
    var missing: [MealIngredient]
    var usesSoon: [String]

    var id: UUID { meal.id }
}

enum IngredientMatch {
    /// The words of a name, lowercased and made singular, so "Baby Spinach" and "spinach" compare.
    static func words(_ name: String) -> [String] {
        name.lowercased().split(whereSeparator: { !$0.isLetter }).map { singular(String($0)) }
    }

    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
    }

    /// Whether something at home covers a recipe ingredient. The last word, what the thing is, has to
    /// match, and every word of the shorter name has to be in the longer one. So "spinach" and "baby
    /// spinach" cover each other, but "cream" doesn't cover "cream cheese".
    static func covers(_ stock: String, _ ingredient: String) -> Bool {
        let a = words(stock), b = words(ingredient)
        guard let headA = a.last, let headB = b.last, headA == headB else { return false }
        let (short, long) = a.count <= b.count ? (Set(a), Set(b)) : (Set(b), Set(a))
        return short.isSubset(of: long)
    }
}

extension GroceryStore {
    /// Saved meals you can make with at least one thing at home. Meals that use up something
    /// going off soon come first, then those needing the fewest extra ingredients.
    func mealsFromHome(now: Date = Date()) -> [MealMatch] {
        let soon = Set(usingSoon(now: now).map(\.name))
        return meals.compactMap { meal -> MealMatch? in
            var have: [String] = [], missing: [MealIngredient] = []
            for ingredient in meal.ingredients {
                if let entry = stock.first(where: { IngredientMatch.covers($0.name, ingredient.name) }) {
                    have.append(entry.name)
                } else {
                    missing.append(ingredient)
                }
            }
            guard !have.isEmpty else { return nil }
            return MealMatch(meal: meal, have: have, missing: missing, usesSoon: have.filter(soon.contains))
        }
        .sorted { a, b in
            if a.usesSoon.count != b.usesSoon.count { return a.usesSoon.count > b.usesSoon.count }
            if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
            return a.meal.name.localizedCaseInsensitiveCompare(b.meal.name) == .orderedAscending
        }
    }

    /// Puts only the ingredients you don't have on the list. Returns how many were added.
    @discardableResult
    func addMissing(_ match: MealMatch, shopID: UUID?) -> Int {
        for ingredient in match.missing {
            let scaled = ingredient.scaled(by: 1)
            addOrBump(name: ingredient.name, quantity: scaled.quantity, aisle: ingredient.aisle,
                      shopID: shopID, inferShop: shopID == nil, note: scaled.note)
        }
        return match.missing.count
    }

    /// Adds an idea's extra ingredients to the list, skipping anything already there or at home.
    @discardableResult
    func addMissing(_ names: [String], shopID: UUID?) -> Int {
        var added = 0
        for name in names where !isOnList(name) && !stock.contains(where: { IngredientMatch.covers($0.name, name) }) {
            addOrBump(name: name, shopID: shopID, inferShop: shopID == nil)
            added += 1
        }
        return added
    }

    /// Saves an idea as a meal and plans it for `day`, so it shows on the meal plan.
    @discardableResult
    func saveIdea(_ idea: CookIdea, planOn day: Date? = nil) -> Meal {
        let ingredients = (idea.uses + idea.extras).map {
            MealIngredient(name: $0, aisle: resolveAisle(for: $0))
        }
        let meal = Meal(name: idea.title, ingredients: ingredients)
        meals.append(meal)
        if let day { addPlan(meal, on: day) }
        return meal
    }
}

/// A dish the on-device model suggested from what's at home.
struct CookIdea: Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// Things at home it uses.
    var uses: [String]
    /// Things you'd need to buy.
    var extras: [String]
    var summary: String
}
