import Foundation

/// The part of Family Sharing that doesn't need iCloud: which files a family list shares, and lining up this
/// phone's entries with the family's before the first merge. FamilySync (in the app) moves the bytes.
extension GroceryStore {
    /// What a family list shares: everything the app keeps, so the whole household works from one list, one
    /// kitchen, one set of meals, one budget and one set of Save Up goals. Files that others point into come
    /// first (stores before items, meals before the meal plan) so this phone's entries can be lined up with the
    /// family's before what refers to them arrives. Only this phone's look (color, icon) and its syncing setup
    /// stay its own, since those aren't saved in these files.
    static let familyFileNames = ["shops", "customAisles", "people", "registryPeople", "allergies", "meals", "plan",
                                  "favorites", "recurring", "history", "stock", "spending", "goals", "settings", "grocery"]

    /// Before this phone first combines one file with the family's copy: anything here that is the same as
    /// one of theirs (a store, aisle or person with the same name, or an item still needed from the same
    /// store) takes the family's id, so joining a family list doesn't list anything twice. Copies that can't
    /// be read change nothing.
    func adoptFamilyIDs(name: String, remote: Data) {
        let decoder = JSONDecoder()
        switch name {
        case "shops":
            guard let theirs = try? decoder.decode([Shop].self, from: remote) else { return }
            remapShops(Self.matchingIDs(ours: shops, theirs: theirs) { Self.same($0.name, $1.name) })
        case "customAisles":
            guard let theirs = try? decoder.decode([CustomAisle].self, from: remote) else { return }
            remapCustomAisles(Self.matchingIDs(ours: customAisles, theirs: theirs) { Self.same($0.name, $1.name) })
        case "people":
            guard let theirs = try? decoder.decode([Person].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: people, theirs: theirs) { Self.same($0.name, $1.name) }
            guard !map.isEmpty else { return }
            people = people.map { var person = $0; person.id = map[person.id] ?? person.id; return person }
            items = items.map { var item = $0; item.personID = item.personID.map { map[$0] ?? $0 }; return item }
        case "registryPeople":
            guard let theirs = try? decoder.decode([RegistryPerson].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: registryPeople, theirs: theirs) { Self.same($0.name, $1.name) }
            guard !map.isEmpty else { return }
            registryPeople = registryPeople.map { var person = $0; person.id = map[person.id] ?? person.id; return person }
            items = items.map { var item = $0; item.giftForID = item.giftForID.map { map[$0] ?? $0 }; return item }
        case "allergies":
            guard let theirs = try? decoder.decode([Allergy].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: allergies, theirs: theirs) { Self.same($0.name, $1.name) }
            guard !map.isEmpty else { return }
            allergies = allergies.map { var allergy = $0; allergy.id = map[allergy.id] ?? allergy.id; return allergy }
        case "meals":
            guard let theirs = try? decoder.decode([Meal].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: meals, theirs: theirs) { Self.same($0.name, $1.name) }
            guard !map.isEmpty else { return }
            meals = meals.map { var meal = $0; meal.id = map[meal.id] ?? meal.id; return meal }
            plan = plan.map { var entry = $0; entry.mealID = map[entry.mealID] ?? entry.mealID; return entry }
        case "plan":
            guard let theirs = try? decoder.decode([PlannedMeal].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: plan, theirs: theirs) {
                $0.mealID == $1.mealID && Calendar.current.isDate($0.day, inSameDayAs: $1.day)
            }
            plan = plan.map { var entry = $0; entry.id = map[entry.id] ?? entry.id; return entry }
        case "favorites":
            guard let theirs = try? decoder.decode([Favorite].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: favorites, theirs: theirs) { Self.same($0.name, $1.name) }
            favorites = favorites.map { var favorite = $0; favorite.id = map[favorite.id] ?? favorite.id; return favorite }
        case "recurring":
            guard let theirs = try? decoder.decode([RecurringItem].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: recurring, theirs: theirs) { Self.same($0.name, $1.name) }
            recurring = recurring.map { var entry = $0; entry.id = map[entry.id] ?? entry.id; return entry }
        case "stock":
            // The same food bought the same day on both phones is one thing in the kitchen.
            guard let theirs = try? decoder.decode([StockEntry].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: stock, theirs: theirs) {
                Self.same($0.name, $1.name) && Calendar.current.isDate($0.bought, inSameDayAs: $1.bought)
            }
            stock = stock.map { var entry = $0; entry.id = map[entry.id] ?? entry.id; return entry }
        case "goals":
            guard let theirs = try? decoder.decode([Goal].self, from: remote) else { return }
            let map = Self.matchingIDs(ours: goals, theirs: theirs) { Self.same($0.name, $1.name) && $0.reserve == $1.reserve }
            goals = goals.map { var goal = $0; goal.id = map[goal.id] ?? goal.id; return goal }
        case "settings":
            // The family's budget and monthly savings win over the ones this phone had before joining.
            guard let theirs = try? decoder.decode([HouseholdSetting].self, from: remote) else { return }
            let theirIDs = Set(theirs.map(\.id))
            if settings.contains(where: { theirIDs.contains($0.id) }) { settings.removeAll { theirIDs.contains($0.id) } }
        case "grocery":
            guard let theirs = try? decoder.decode([GroceryItem].self, from: remote) else { return }
            // Only items still needed: a bought item on one phone and a needed one on the other are two trips.
            let map = Self.matchingIDs(ours: items.filter { !$0.isChecked }, theirs: theirs.filter { !$0.isChecked }, matches: Self.sameItem)
            guard !map.isEmpty else { return }
            items = items.map { var item = $0; item.id = map[item.id] ?? item.id; return item }
        default:
            return
        }
    }

    /// For each of ours that the family doesn't have by id, the id of the family's entry that `matches` it, if
    /// there is one that isn't already matched. Entries with the same id on both sides are already lined up.
    static func matchingIDs<Element: Identifiable>(ours: [Element], theirs: [Element], matches: (Element, Element) -> Bool) -> [UUID: UUID]
    where Element.ID == UUID {
        let ourIDs = Set(ours.map(\.id))
        var available = theirs.filter { !ourIDs.contains($0.id) }
        let theirIDs = Set(theirs.map(\.id))
        var map: [UUID: UUID] = [:]
        for entry in ours where !theirIDs.contains(entry.id) {
            guard let index = available.firstIndex(where: { matches(entry, $0) }) else { continue }
            map[entry.id] = available.remove(at: index).id
        }
        return map
    }

    /// The same item twice: same name (singular or plural), same store, same list chip, and for the same person.
    private static func sameItem(_ a: GroceryItem, _ b: GroceryItem) -> Bool {
        a.shopID == b.shopID && a.list == b.list && a.personID == b.personID && a.giftForID == b.giftForID && same(a.name, b.name)
    }

    /// Gives stores new ids everywhere they're used: the list, history and prices, repeating items and spending.
    private func remapShops(_ map: [UUID: UUID]) {
        guard !map.isEmpty else { return }
        func new(_ id: UUID?) -> UUID? { id.map { map[$0] ?? $0 } }
        shops = shops.map { var shop = $0; shop.id = map[shop.id] ?? shop.id; return shop }
        items = items.map { var item = $0; item.shopID = new(item.shopID); return item }
        recurring = recurring.map { var entry = $0; entry.shopID = new(entry.shopID); return entry }
        spending = spending.map { var record = $0; record.shopID = new(record.shopID); return record }
        history = history.map { past in
            var past = past
            past.shopID = new(past.shopID)
            past.priceHistory = past.priceHistory?.map { var point = $0; point.shopID = new(point.shopID); return point }
            return past
        }
    }

    /// Gives custom aisles new ids on the items in them and in each store's aisle order.
    private func remapCustomAisles(_ map: [UUID: UUID]) {
        guard !map.isEmpty else { return }
        customAisles = customAisles.map { var aisle = $0; aisle.id = map[aisle.id] ?? aisle.id; return aisle }
        items = items.map { var item = $0; item.customAisleID = item.customAisleID.map { map[$0] ?? $0 }; return item }
        let byString = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value.uuidString) })
        shops = shops.map { shop in
            guard let anchors = shop.customAnchors else { return shop }
            var shop = shop
            shop.customAnchors = Dictionary(anchors.map { (byString[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            return shop
        }
    }
}

/// What a Family Sharing invite says, so whoever gets it knows who sent it and what tapping it does.
enum FamilyInvite {
    private static func trimmed(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The title on the invite's link card and on the share itself.
    static func title(from name: String) -> String {
        trimmed(name).map { "\($0)'s grocery list" } ?? "Shared grocery list"
    }

    /// The message sent with the link, above it.
    static func message(from name: String) -> String {
        let opening = trimmed(name).map { "\($0) invited you to share a grocery list in Makin' Groceries." }
            ?? "You're invited to share a grocery list in Makin' Groceries."
        return opening + " Tap the link below on your iPhone to join. You'll both see the same list on your own phones, and anything added or checked off shows up for everyone. You'll need the Makin' Groceries app and an iCloud account."
    }
}
