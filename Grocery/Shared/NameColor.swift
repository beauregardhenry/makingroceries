import Foundation

/// The colors a person's header can be on the Clothing and Registry lists. Until you pick one, people get the
/// colors in this order by their place in the list.
enum NameColor: String, CaseIterable, Identifiable {
    case blue, pink, green, orange, purple, teal, red, indigo, yellow, mint, cyan, brown

    var id: String { rawValue }

    /// How it's named in the color menu.
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The color picked (`stored`), or else the one for someone at `index` in the list.
    static func resolved(_ stored: String?, index: Int) -> NameColor {
        if let stored, let picked = NameColor(rawValue: stored) { return picked }
        let defaults = Array(allCases.prefix(8))
        return defaults[((index % defaults.count) + defaults.count) % defaults.count]
    }
}

extension GroceryStore {
    /// The header color of someone on the Clothing list.
    func color(ofPerson id: UUID) -> NameColor {
        let index = people.firstIndex { $0.id == id } ?? 0
        return NameColor.resolved(people.first { $0.id == id }?.color, index: index)
    }

    /// The header color of someone on the Registry list.
    func color(ofRegistryPerson id: UUID) -> NameColor {
        let index = registryPeople.firstIndex { $0.id == id } ?? 0
        return NameColor.resolved(registryPeople.first { $0.id == id }?.color, index: index)
    }

    func setColor(_ color: NameColor, ofPerson id: UUID) {
        guard let i = people.firstIndex(where: { $0.id == id }) else { return }
        people[i].color = color.rawValue
    }

    func setColor(_ color: NameColor, ofRegistryPerson id: UUID) {
        guard let i = registryPeople.firstIndex(where: { $0.id == id }) else { return }
        registryPeople[i].color = color.rawValue
    }
}
