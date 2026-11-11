import Foundation

/// Someone gifts are kept for, with an optional birthday.
struct RegistryPerson: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var birthday: Date?
}

enum RegistryOccasion {
    static let all = ["Birthday", "Christmas", "Hanukkah", "Anniversary", "Wedding", "Baby shower", "Graduation", "Mother's Day", "Father's Day", "Other"]
}

extension GroceryStore {
    @discardableResult
    func addRegistryPerson(named name: String, birthday: Date? = nil) -> RegistryPerson? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !registryPeople.contains(where: { Self.same($0.name, trimmed) }) else { return nil }
        let person = RegistryPerson(name: trimmed, birthday: birthday)
        registryPeople.append(person)
        return person
    }

    func registryPerson(for id: UUID?) -> RegistryPerson? {
        guard let id else { return nil }
        return registryPeople.first { $0.id == id }
    }

    /// Gifts for someone who is deleted stay on the list, under "No one yet".
    func deleteRegistryPerson(_ id: UUID) {
        registryPeople.removeAll { $0.id == id }
        for i in items.indices where items[i].giftForID == id { items[i].giftForID = nil }
    }

    func move(_ item: GroceryItem, toGiftFor id: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].giftForID = id
    }

    /// Gifts under a header for each person, in the order of your registry list, then any without a person.
    /// Within a person, what is still needed comes before what is bought.
    func registrySections(_ gifts: [GroceryItem]) -> [(person: RegistryPerson?, items: [GroceryItem])] {
        func ordered(_ list: [GroceryItem]) -> [GroceryItem] {
            list.filter { !$0.isChecked } + list.filter(\.isChecked)
        }
        var result: [(person: RegistryPerson?, items: [GroceryItem])] = registryPeople.compactMap { person in
            let mine = gifts.filter { $0.giftForID == person.id }
            return mine.isEmpty ? nil : (person, ordered(mine))
        }
        let known = Set(registryPeople.map(\.id))
        let loose = gifts.filter { $0.giftForID == nil || !known.contains($0.giftForID!) }
        if !loose.isEmpty { result.append((nil, ordered(loose))) }
        return result
    }
}

enum RegistryInfo {
    /// The lines at the top of a gift's long-press menu.
    static func lines(for item: GroceryItem, dateText: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }) -> [String] {
        var lines: [String] = []
        if let added = item.addedAt { lines.append("Added \(dateText(added))") }
        if let occasion = item.occasion, !occasion.isEmpty { lines.append("For \(occasion)") }
        if item.isChecked { lines.append(item.boughtAt.map { "Bought \(dateText($0))" } ?? "Bought") }
        return lines
    }

    /// "Birthday Mar 4", for a person's header.
    static func birthdayText(_ person: RegistryPerson?, format: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }) -> String? {
        person?.birthday.map { "Birthday \(format($0))" }
    }

    /// The list as text for someone without the app: each person as a heading with the gifts still needed.
    static func shareText(gifts: [GroceryItem], sections: [(person: RegistryPerson?, items: [GroceryItem])]) -> String {
        var lines = ["Gift list"]
        for group in sections {
            let needed = group.items.filter { !$0.isChecked }
            guard !needed.isEmpty else { continue }
            var header = group.person?.name ?? "Not assigned yet"
            if let birthday = birthdayText(group.person) { header += " (\(birthday))" }
            lines += ["", header]
            for item in needed {
                var line = "☐ \(item.name)"
                if item.quantity > 1 { line += " ×\(item.quantity)" }
                if let occasion = item.occasion, !occasion.isEmpty { line += " (\(occasion))" }
                lines.append(line)
            }
        }
        if lines.count == 1 { lines.append("") ; lines.append("Nothing needed right now.") }
        return lines.joined(separator: "\n")
    }
}
