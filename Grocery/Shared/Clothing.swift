import Foundation

extension GroceryStore {
    // MARK: People

    @discardableResult
    func addPerson(named name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !people.contains(where: { Self.same($0.name, trimmed) }) else { return nil }
        let person = Person(name: trimmed)
        people.append(person)
        return person
    }

    func person(for id: UUID?) -> Person? {
        guard let id else { return nil }
        return people.first { $0.id == id }
    }

    /// Clothing for someone who is deleted stays on the list, under "No one yet".
    func deletePerson(_ id: UUID) {
        people.removeAll { $0.id == id }
        for i in items.indices where items[i].personID == id { items[i].personID = nil }
    }

    // MARK: Sizes

    func rememberSize(_ size: String, for personID: UUID?, itemNamed name: String) {
        guard let i = people.firstIndex(where: { $0.id == personID }) else { return }
        var sizes = people[i].sizes ?? [:]
        sizes[name.lowercased()] = size
        people[i].sizes = sizes
    }

    /// The last size used for this kind of item for this person, to suggest.
    func lastSize(for personID: UUID?, itemNamed name: String) -> String? {
        person(for: personID)?.sizes?[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    func move(_ item: GroceryItem, toPerson personID: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].personID = personID
    }

    /// Sets an item's size, noting when it changed. A blank size clears it.
    func setClothingSize(_ size: String?, for id: UUID, on date: Date = Date()) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = size?.trimmingCharacters(in: .whitespaces)
        let new = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard new != items[i].clothingSize else { return }
        items[i].clothingSize = new
        items[i].sizeDate = new == nil ? nil : date
        if let new { rememberSize(new, for: items[i].personID, itemNamed: items[i].name) }
    }

    // MARK: Grouping

    /// Clothing under a header for each person, in the order of your family list, then anything without a person.
    func clothingSections(_ clothing: [GroceryItem]) -> [(person: Person?, items: [GroceryItem])] {
        var result: [(person: Person?, items: [GroceryItem])] = people.compactMap { person in
            let mine = clothing.filter { $0.personID == person.id }
            return mine.isEmpty ? nil : (person, mine)
        }
        let known = Set(people.map(\.id))
        let loose = clothing.filter { $0.personID == nil || !known.contains($0.personID!) }
        if !loose.isEmpty { result.append((nil, loose)) }
        return result
    }
}

enum ClothingInfo {
    /// The lines at the top of a clothing item's long-press menu: when it was added, and its size and when
    /// that was set. Nothing here shows on the list row.
    static func lines(for item: GroceryItem, dateText: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }) -> [String] {
        var lines: [String] = []
        if let added = item.addedAt { lines.append("Added \(dateText(added))") }
        if let size = item.clothingSize, !size.isEmpty {
            var line = "Size \(size)"
            if let date = item.sizeDate, item.addedAt.map({ !Calendar.current.isDate($0, inSameDayAs: date) }) ?? true {
                line += " · set \(dateText(date))"
            }
            lines.append(line)
        } else {
            lines.append("No size yet")
        }
        return lines
    }
}
