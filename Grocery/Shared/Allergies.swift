import Foundation

/// A food to avoid, with what it does to you. Kept with the other lists, so it syncs with iCloud and is
/// shared with family on a shared list.
struct Allergy: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// What it does to you, by `AllergyReaction.rawValue`.
    var reactions: [String]?
    /// A category picked by hand, by `AllergyCategory.rawValue`; nil means the one guessed from the name.
    var categoryOverride: String?

    var category: AllergyCategory {
        categoryOverride.flatMap(AllergyCategory.init(rawValue:)) ?? AllergyCategory.guess(for: name)
    }

    /// The reactions picked, in the order they're offered.
    var reactionList: [AllergyReaction] {
        let picked = Set(reactions ?? [])
        return AllergyReaction.allCases.filter { picked.contains($0.rawValue) }
    }
}

/// What an allergy does to you.
enum AllergyReaction: String, CaseIterable, Identifiable {
    case anaphylaxis = "Anaphylaxis"
    case breathing = "Trouble Breathing"
    case swelling = "Swelling"
    case hives = "Hives or Rash"
    case itching = "Itching"
    case nausea = "Nausea or Vomiting"
    case stomach = "Stomach Pain"
    case diarrhea = "Diarrhea"
    case headache = "Headache"
    case congestion = "Stuffy or Runny Nose"
    case intolerance = "Intolerance"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .anaphylaxis: "staroflife.fill"
        case .breathing: "lungs.fill"
        case .swelling: "drop.fill"
        case .hives: "allergens"
        case .itching: "hand.raised.fill"
        case .nausea, .stomach, .diarrhea: "cross.case.fill"
        case .headache: "brain.head.profile"
        case .congestion: "nose"
        case .intolerance: "exclamationmark.circle"
        }
    }

    /// Life-threatening reactions, shown first and called out in warnings.
    var isSevere: Bool { self == .anaphylaxis || self == .breathing }
}

/// The sections of the Allergies list, in the order they're shown.
enum AllergyCategory: String, CaseIterable, Identifiable {
    case nuts = "Nuts"
    case dairy = "Dairy"
    case eggs = "Eggs"
    case grains = "Grains & Gluten"
    case seafood = "Fish & Shellfish"
    case soy = "Soy & Legumes"
    case seeds = "Seeds & Spices"
    case produce = "Fruits & Vegetables"
    case meat = "Meat"
    case additives = "Additives"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .nuts: "leaf.fill"
        case .dairy: "cup.and.saucer.fill"
        case .eggs: "oval.portrait.fill"
        case .grains: "laurel.leading"
        case .seafood: "fish.fill"
        case .soy: "circle.grid.2x2.fill"
        case .seeds: "sparkles"
        case .produce: "carrot.fill"
        case .meat: "fork.knife"
        case .additives: "flask.fill"
        case .other: "questionmark.circle"
        }
    }

    private static let keywords: [(AllergyCategory, Set<String>)] = [
        (.nuts, ["nut", "peanut", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "filbert"]),
        (.dairy, ["milk", "dairy", "lactose", "cheese", "butter", "cream", "whey", "casein", "yogurt"]),
        (.eggs, ["egg"]),
        (.grains, ["gluten", "wheat", "oat", "barley", "rye", "corn", "rice", "yeast", "spelt"]),
        (.seafood, ["fish", "shellfish", "shrimp", "crab", "lobster", "clam", "oyster", "mussel", "mollusk", "scallop",
                    "salmon", "tuna", "crustacean", "squid"]),
        (.soy, ["soy", "soybean", "lupin", "lentil", "chickpea", "bean", "pea"]),
        (.seeds, ["sesame", "mustard", "sunflower", "poppy", "cinnamon", "nutmeg", "paprika", "cumin", "spice", "seed"]),
        (.produce, ["kiwi", "strawberry", "tomato", "garlic", "onion", "pepper", "avocado", "banana", "celery",
                    "nightshade", "apple", "peach", "citrus", "orange", "mango", "coconut", "potato", "berry"]),
        (.meat, ["pork", "beef", "chicken", "lamb", "turkey", "gelatin", "meat"]),
        (.additives, ["sulfite", "msg", "dye", "caffeine", "alcohol", "nitrate", "aspartame", "sweetener", "preservative"]),
    ]

    /// The section a name belongs in, from its words; Other when nothing matches.
    static func guess(for name: String) -> AllergyCategory {
        let words = name.lowercased().split { !$0.isLetter }.map { GroceryStore.stem(String($0)) }
        for (category, names) in keywords where words.contains(where: names.contains) {
            return category
        }
        return .other
    }
}

extension GroceryStore {
    /// The Allergies list: one section per category in a fixed order, each alphabetized; empty sections left out.
    var allergyGroups: [(category: AllergyCategory, allergies: [Allergy])] {
        let byCategory = Dictionary(grouping: allergies, by: \.category)
        return AllergyCategory.allCases.compactMap { category in
            guard let group = byCategory[category], !group.isEmpty else { return nil }
            return (category, group.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    /// Adds an allergy in title case, unless it's blank, under three letters, or already there (singular or plural).
    @discardableResult
    func addAllergy(named name: String) -> Allergy? {
        let trimmed = TitleCase.apply(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard trimmed.count >= 3, !allergies.contains(where: { Self.same($0.name, trimmed) }) else { return nil }
        let allergy = Allergy(name: trimmed)
        allergies.append(allergy)
        return allergy
    }

    func deleteAllergy(_ id: UUID) {
        allergies.removeAll { $0.id == id }
    }

    func toggleReaction(_ reaction: AllergyReaction, for id: UUID) {
        guard let i = allergies.firstIndex(where: { $0.id == id }) else { return }
        var picked = allergies[i].reactions ?? []
        if let found = picked.firstIndex(of: reaction.rawValue) { picked.remove(at: found) } else { picked.append(reaction.rawValue) }
        allergies[i].reactions = picked.isEmpty ? nil : picked
    }

    /// Files an allergy under `category`, or back under the guessed one with nil.
    func setCategory(_ category: AllergyCategory?, for id: UUID) {
        guard let i = allergies.firstIndex(where: { $0.id == id }) else { return }
        let guessed = AllergyCategory.guess(for: allergies[i].name)
        allergies[i].categoryOverride = category == guessed ? nil : category?.rawValue
    }

    /// Product warnings for what's on the Allergies list, naming a severe reaction when one is noted.
    func allergyWarning(allergens: [String], ingredients: String?) -> String? {
        let found = AvoidList.warnings(allergens: allergens, ingredients: ingredients, avoid: allergies.map(\.name))
        guard let message = AvoidList.message(found) else { return nil }
        let severe = allergies.filter { allergy in
            found.contains { Self.same($0, allergy.name) } && allergy.reactionList.contains(where: \.isSevere)
        }
        return severe.isEmpty ? message : message + ". Severe reaction: " + severe.map(\.name).joined(separator: ", ").lowercased()
    }

    /// Moves the avoid list this phone used to keep to itself into the synced Allergies list, once.
    func moveOldAvoidList(defaults: UserDefaults = .standard) {
        let old = defaults.stringArray(forKey: "avoidWords") ?? []
        guard !old.isEmpty else { return }
        for word in old { addAllergy(named: word) }
        defaults.removeObject(forKey: "avoidWords")
    }
}
