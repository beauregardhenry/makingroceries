import Foundation

/// A meal planned for a particular day.
struct PlannedMeal: Identifiable, Codable, Equatable {
    var id = UUID()
    var mealID: UUID
    /// Start of the day it's planned for.
    var day: Date
    /// Set once its ingredients have been put on the list, so they aren't added twice.
    var onList: Bool?
}

extension GroceryStore {
    func planned(on day: Date) -> [PlannedMeal] {
        plan.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    func addPlan(_ meal: Meal, on day: Date) {
        plan.append(PlannedMeal(mealID: meal.id, day: Calendar.current.startOfDay(for: day)))
    }

    func removePlan(_ id: UUID) {
        plan.removeAll { $0.id == id }
    }

    /// Plans for today and later whose meal still exists, oldest first.
    func upcomingPlan(from start: Date = Date()) -> [PlannedMeal] {
        let today = Calendar.current.startOfDay(for: start)
        let known = Set(meals.map(\.id))
        return plan.filter { $0.day >= today && known.contains($0.mealID) }.sorted { $0.day < $1.day }
    }

    /// Puts the ingredients of every planned meal in the next `days` days on the list. Meals already
    /// added aren't added again. Returns how many meals were added.
    @discardableResult
    func addPlannedToList(days: Int, shopID: UUID?, from start: Date = Date()) -> Int {
        let today = Calendar.current.startOfDay(for: start)
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: today) else { return 0 }
        var added = 0
        for i in plan.indices where plan[i].day >= today && plan[i].day < end && plan[i].onList != true {
            guard let meal = meals.first(where: { $0.id == plan[i].mealID }) else { continue }
            addToList(meal, shopID: shopID)
            plan[i].onList = true
            added += 1
        }
        return added
    }
}
