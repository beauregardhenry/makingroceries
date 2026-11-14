import Foundation

/// The colors a person's header can be on the Clothing and Registry lists. Until you pick one, people get the
/// colors in this order by their place in the list.
enum NameColor: String, CaseIterable, Identifiable {
    case blue, pink, green, orange, purple, teal, red, indigo, yellow, mint, cyan, brown

    var id: String { rawValue }

    /// Light colors that read better with dark text on a solid band.
    var prefersDarkText: Bool { self == .yellow || self == .mint || self == .cyan }

    /// How it's named in the color menu.
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The color picked (`stored`), or else the one `name` always starts with, so the same name gets the same
    /// color on every list and every phone.
    static func resolved(_ stored: String?, name: String) -> NameColor {
        if let stored, let picked = NameColor(rawValue: stored) { return picked }
        let defaults = Array(allCases.prefix(8))
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // A small fixed hash (not Swift's hashValue, which changes every launch).
        let hash = key.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return defaults[Int(hash % UInt32(defaults.count))]
    }
}

extension GroceryStore {
    /// Someone's color, the same everywhere their name appears: Family Members, Registry People, and the
    /// Clothing and Registry headers. A color picked for either of them counts for both.
    func color(named name: String) -> NameColor {
        let picked = people.first { Self.same($0.name, name) && $0.color != nil }?.color
            ?? registryPeople.first { Self.same($0.name, name) && $0.color != nil }?.color
        return NameColor.resolved(picked, name: name)
    }

    /// The header color of someone on the Clothing list.
    func color(ofPerson id: UUID) -> NameColor {
        color(named: people.first { $0.id == id }?.name ?? "")
    }

    /// The header color of someone on the Registry list.
    func color(ofRegistryPerson id: UUID) -> NameColor {
        color(named: registryPeople.first { $0.id == id }?.name ?? "")
    }

    /// Gives a name a color on both lists, so it's the same everywhere.
    func setColor(_ color: NameColor, named name: String) {
        for i in people.indices where Self.same(people[i].name, name) && people[i].color != color.rawValue {
            people[i].color = color.rawValue
        }
        for i in registryPeople.indices where Self.same(registryPeople[i].name, name) && registryPeople[i].color != color.rawValue {
            registryPeople[i].color = color.rawValue
        }
    }

    func setColor(_ color: NameColor, ofPerson id: UUID) {
        guard let person = people.first(where: { $0.id == id }) else { return }
        setColor(color, named: person.name)
    }

    func setColor(_ color: NameColor, ofRegistryPerson id: UUID) {
        guard let person = registryPeople.first(where: { $0.id == id }) else { return }
        setColor(color, named: person.name)
    }
}
