import Foundation

/// One saved size or measurement for a family member, like "Shoes: 7" or "Inseam: 30 in", with when it was set.
struct Measurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var value: String
    var updated: Date
}

enum MeasurementLabels {
    /// Offered when adding a measurement, in this order.
    static let common = ["Shirt", "Pants", "Dress", "Jacket", "Shoes", "Socks", "Underwear", "Hat", "Gloves", "Ring",
                         "Height", "Weight", "Chest", "Waist", "Hips", "Inseam", "Neck", "Sleeve"]

    /// Item words that mean a measurement's label, so "Jeans" suggests the Pants size.
    static let synonyms: [String: String] = [
        "jean": "Pants", "trouser": "Pants", "short": "Pants", "legging": "Pants", "slack": "Pants", "chino": "Pants",
        "tee": "Shirt", "t-shirt": "Shirt", "top": "Shirt", "blouse": "Shirt", "polo": "Shirt", "sweater": "Shirt",
        "hoodie": "Shirt", "sweatshirt": "Shirt",
        "sneaker": "Shoes", "boot": "Shoes", "sandal": "Shoes", "cleat": "Shoes", "slipper": "Shoes", "heel": "Shoes",
        "coat": "Jacket", "parka": "Jacket", "skirt": "Dress", "cap": "Hat", "beanie": "Hat", "mitten": "Gloves",
        "brief": "Underwear", "boxer": "Underwear", "bra": "Underwear",
    ]
}

extension GroceryStore {
    /// Adds an empty measurement for someone, unless they already have one with that label.
    @discardableResult
    func addMeasurement(_ label: String, for personID: UUID, on date: Date = Date()) -> Measurement? {
        let trimmed = TitleCase.apply(label.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty, let i = people.firstIndex(where: { $0.id == personID }),
              !(people[i].measurements ?? []).contains(where: { Self.same($0.label, trimmed) }) else { return nil }
        let measurement = Measurement(label: trimmed, value: "", updated: date)
        people[i].measurements = (people[i].measurements ?? []) + [measurement]
        return measurement
    }

    /// Sets a measurement's value, noting the date when it changes.
    func setMeasurement(_ id: UUID, to value: String, for personID: UUID, on date: Date = Date()) {
        guard let p = people.firstIndex(where: { $0.id == personID }),
              let m = people[p].measurements?.firstIndex(where: { $0.id == id }),
              people[p].measurements?[m].value != value else { return }
        people[p].measurements?[m].value = value
        people[p].measurements?[m].updated = date
    }

    func removeMeasurement(_ id: UUID, for personID: UUID) {
        guard let p = people.firstIndex(where: { $0.id == personID }) else { return }
        people[p].measurements?.removeAll { $0.id == id }
        if people[p].measurements?.isEmpty == true { people[p].measurements = nil }
    }

    /// The size to suggest for a clothing item: the last size used for that item for this person, or else a
    /// saved measurement that fits it ("Running Shoes" → Shoes, "Jeans" → Pants).
    func suggestedSize(for personID: UUID?, itemNamed name: String) -> String? {
        if let last = lastSize(for: personID, itemNamed: name) { return last }
        let saved = (person(for: personID)?.measurements ?? []).filter {
            !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !saved.isEmpty else { return nil }
        let words = name.lowercased().split { $0 == " " || $0 == "," }.map(String.init)
        for word in words.reversed() {
            if let match = saved.first(where: { Self.same($0.label, word) }) { return match.value }
            let base = GroceryStore.stem(word)
            if let label = MeasurementLabels.synonyms[base] ?? MeasurementLabels.synonyms[word],
               let match = saved.first(where: { Self.same($0.label, label) }) {
                return match.value
            }
        }
        return nil
    }
}
