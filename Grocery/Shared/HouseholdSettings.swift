import Foundation

/// A setting the whole household shares, like the grocery budget. Kept as a list so it syncs with iCloud and on
/// a family list the same way as everything else; each setting's name is its id, so the same setting on two
/// phones merges into one.
struct HouseholdSetting: Identifiable, Codable, Equatable {
    var id: String
    var number: Double?
}

extension GroceryStore {
    private func number(_ key: String) -> Double? {
        settings.first { $0.id == key }?.number
    }

    private func setNumber(_ value: Double?, _ key: String) {
        let value = value.flatMap { $0 > 0 ? $0 : nil }
        if let i = settings.firstIndex(where: { $0.id == key }) {
            if settings[i].number != value { settings[i].number = value }
        } else if value != nil {
            settings.append(HouseholdSetting(id: key, number: value))
        }
    }

    /// What you'd like to spend on groceries each month (Money). Nil when not set.
    var monthlyBudget: Double? {
        get { number("monthlyBudget") }
        set { setNumber(newValue, "monthlyBudget") }
    }

    /// How much you can put toward Save Up goals each month. Zero when not set.
    var savePerMonth: Double {
        get { number("savePerMonth") ?? 0 }
        set { setNumber(newValue, "savePerMonth") }
    }

    /// Moves the budget and monthly savings this phone used to keep to itself into the shared settings, once.
    func moveOldSettings(defaults: UserDefaults = .standard) {
        for key in ["monthlyBudget", "savePerMonth"] where defaults.object(forKey: key) != nil {
            let old = defaults.double(forKey: key)
            if old > 0, number(key) == nil { setNumber(old, key) }
            defaults.removeObject(forKey: key)
        }
    }
}
