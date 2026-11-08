import Foundation

/// An event from the phone's calendar. Google Calendar events show up here too when the Google account is
/// added in Settings › Calendar › Accounts, so the app never needs a Google sign-in of its own.
struct CalendarEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var attendeeCount: Int = 0
    var isAllDay = false
    var calendarName: String?
}

enum CompanyEvents {
    /// Words in an event's title that mean people are coming to eat.
    static let keywords = [
        "dinner", "lunch", "brunch", "party", "guests", "company", "visit", "visiting", "cookout", "bbq",
        "barbecue", "potluck", "shower", "gathering", "hosting", "reunion", "holiday", "thanksgiving",
        "christmas", "easter", "birthday", "celebration", "get-together", "open house", "playdate",
    ]

    /// Whether an event looks like having company over: a food or party word in the title, or a
    /// good-sized guest list. Events titled "Dentist" or "Standup" aren't.
    static func looksLikeCompany(_ event: CalendarEvent) -> Bool {
        let title = event.title.lowercased()
        if keywords.contains(where: { title.contains($0) }) { return true }
        return event.attendeeCount >= 5 && !event.isAllDay
    }

    /// Company events in the next `days` days, soonest first.
    static func upcoming(_ events: [CalendarEvent], from now: Date = Date(), days: Int = 21) -> [CalendarEvent] {
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return events
            .filter { $0.start >= Calendar.current.startOfDay(for: now) && $0.start < end && looksLikeCompany($0) }
            .sorted { $0.start < $1.start }
    }
}

/// A dish that can be made ahead and frozen.
struct MakeAheadIdea: Identifiable, Equatable {
    var title: String
    var note: String
    var ingredients: [String]
    var category: MealCategory
    /// The saved meal this came from, if you already have it.
    var mealID: UUID?

    var id: String { title.lowercased() }
}

enum MakeAhead {
    /// How many days before the event to cook, so there's time to freeze and thaw.
    static let daysAhead = 3

    static func makeByDate(for event: Date, daysAhead: Int = MakeAhead.daysAhead, now: Date = Date()) -> Date {
        let cal = Calendar.current
        let ideal = cal.date(byAdding: .day, value: -daysAhead, to: cal.startOfDay(for: event)) ?? event
        // Never in the past: if the event is soon, cook today.
        return max(ideal, cal.startOfDay(for: now))
    }

    /// Recipes serve about four, so this is the batch size for a crowd, to the nearest half.
    static func scale(forGuests guests: Int) -> Double {
        max(0.5, (Double(max(guests, 1)) / 4 * 2).rounded() / 2)
    }

    static let builtIn: [MakeAheadIdea] = [
        .init(title: "Baked Ziti", note: "Assemble, freeze unbaked, bake from thawed.",
              ingredients: ["Ziti pasta", "Marinara sauce", "Ricotta", "Mozzarella", "Italian sausage"], category: .dinner),
        .init(title: "Lasagna", note: "Freezes whole or in squares. Thaw overnight, then bake.",
              ingredients: ["Lasagna noodles", "Ground beef", "Marinara sauce", "Ricotta", "Mozzarella", "Parmesan"], category: .dinner),
        .init(title: "Chicken Enchiladas", note: "Roll and freeze before baking; add sauce when you bake.",
              ingredients: ["Tortillas", "Chicken breast", "Enchilada sauce", "Shredded cheese", "Black beans"], category: .dinner),
        .init(title: "Meatballs", note: "Cook, cool, freeze flat. Reheat in sauce.",
              ingredients: ["Ground beef", "Breadcrumbs", "Eggs", "Parmesan", "Marinara sauce"], category: .dinner),
        .init(title: "Beef Chili", note: "Better the second day. Freezes for months.",
              ingredients: ["Ground beef", "Kidney beans", "Diced tomatoes", "Onion", "Chili powder"], category: .soup),
        .init(title: "Minestrone Soup", note: "Leave the pasta out and add it when reheating.",
              ingredients: ["Carrots", "Celery", "Onion", "Diced tomatoes", "Cannellini beans", "Vegetable broth"], category: .soup),
        .init(title: "Pulled Pork", note: "Slow cook, shred, freeze with its juices.",
              ingredients: ["Pork shoulder", "BBQ sauce", "Brown sugar", "Slider buns"], category: .dinner),
        .init(title: "Stuffed Shells", note: "Fill, freeze on a tray, then bag. Bake from frozen.",
              ingredients: ["Jumbo pasta shells", "Ricotta", "Spinach", "Marinara sauce", "Mozzarella"], category: .dinner),
        .init(title: "Breakfast Burritos", note: "Wrap individually; reheat in the microwave.",
              ingredients: ["Tortillas", "Eggs", "Breakfast sausage", "Shredded cheese", "Potatoes"], category: .breakfast),
        .init(title: "Cookie Dough", note: "Scoop and freeze; bake fresh when guests arrive.",
              ingredients: ["Flour", "Butter", "Brown sugar", "Chocolate chips", "Eggs"], category: .dessert),
        .init(title: "Banana Bread", note: "Slice and freeze; thaw on the counter.",
              ingredients: ["Bananas", "Flour", "Butter", "Sugar", "Eggs"], category: .dessert),
        .init(title: "Macaroni and Cheese", note: "Undercook the pasta slightly and freeze in a pan.",
              ingredients: ["Elbow macaroni", "Cheddar cheese", "Milk", "Butter", "Breadcrumbs"], category: .side),
    ]

    /// Make-ahead ideas for company: your own meals marked "freezes well" first, then the built-in ideas
    /// you haven't saved yet.
    static func suggestions(meals: [Meal], limit: Int = 12) -> [MakeAheadIdea] {
        let mine = meals.filter(\.freezerFriendly).map {
            MakeAheadIdea(title: $0.name, note: "One of your saved meals.", ingredients: $0.ingredients.map(\.name),
                          category: $0.shownCategory, mealID: $0.id)
        }
        let saved = Set(meals.map { $0.name.lowercased() })
        let more = builtIn.filter { !saved.contains($0.title.lowercased()) }
        return Array((mine + more).prefix(limit))
    }
}

extension Meal {
    /// The category you set, otherwise a guess from the name.
    var shownCategory: MealCategory { category ?? MealCategory.guess(fromName: name) ?? .dinner }
}

extension GroceryStore {
    /// Plans a make-ahead dish for the day to cook it before an event, saving it as a meal first if it came
    /// from the built-in ideas. Returns the meal.
    @discardableResult
    func planMakeAhead(_ idea: MakeAheadIdea, for event: Date, now: Date = Date()) -> Meal {
        let meal = makeAheadMeal(for: idea)
        addPlan(meal, on: MakeAhead.makeByDate(for: event, now: now))
        return meal
    }

    /// The saved meal for an idea, creating it (marked as freezing well) when you don't have it yet.
    func makeAheadMeal(for idea: MakeAheadIdea) -> Meal {
        if let id = idea.mealID, let meal = meals.first(where: { $0.id == id }) { return meal }
        if let meal = meals.first(where: { $0.name.caseInsensitiveCompare(idea.title) == .orderedSame }) { return meal }
        var meal = Meal(name: idea.title, ingredients: idea.ingredients.map {
            MealIngredient(name: $0, aisle: resolveAisle(for: $0))
        })
        meal.category = idea.category
        meal.freezes = true
        meals.append(meal)
        return meal
    }

    /// Puts a make-ahead dish's ingredients on the list, scaled for a crowd.
    func addMakeAheadToList(_ idea: MakeAheadIdea, shopID: UUID?, scale: Double = 1) {
        addToList(makeAheadMeal(for: idea), shopID: shopID, scale: scale)
    }
}
