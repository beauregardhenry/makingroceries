import Foundation

/// Foods you want a warning about, like peanuts or gluten. Kept on the device.
enum AvoidList {
    private static let key = "avoidWords"

    static var words: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Which avoided words show up in a product's allergen tags or ingredient text.
    static func warnings(allergens: [String], ingredients: String?, avoid: [String]) -> [String] {
        let tags = allergens.map { tag in
            (tag.split(separator: ":").last.map(String.init) ?? tag).replacingOccurrences(of: "-", with: " ").lowercased()
        }
        let text = (ingredients ?? "").lowercased()
        var found: [String] = []
        for raw in avoid {
            let word = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard word.count >= 3 else { continue }
            let stem = GroceryStore.stem(word)
            let inTags = tags.contains { GroceryStore.stem($0).contains(stem) }
            let inText = text.contains(stem)
            if inTags || inText, !found.contains(where: { $0.lowercased() == word }) {
                found.append(word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return found
    }

    static func message(_ found: [String]) -> String? {
        found.isEmpty ? nil : "Contains " + found.joined(separator: ", ").lowercased()
    }
}
