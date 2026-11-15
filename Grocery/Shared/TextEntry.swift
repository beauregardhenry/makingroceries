import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Names are kept in title case: each word starts with a capital letter. The rest of each word is left as
/// typed, so "BBQ" and "McCormick" keep their capitals.
enum TitleCase {
    static func apply(_ text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in text {
            if atWordStart, character.isLetter {
                result += character.uppercased()
                atWordStart = false
            } else {
                result.append(character)
                if character.isWhitespace {
                    atWordStart = true
                } else if character.isLetter || character.isNumber {
                    atWordStart = false
                }
            }
        }
        return result
    }
}

/// Singular and plural count as the same name: "Apple" and "apples", "Cookie" and "Cookies", "Peach" and
/// "Peaches". Only the end of the name is looked at, so "Green Apples" matches "green apple".
enum PluralForms {
    /// The name and each singular it could be, lowercased.
    static func keys(_ text: String) -> Set<String> {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var keys: Set<String> = [word]
        if word.count > 4, word.hasSuffix("ies") {
            keys.insert(String(word.dropLast(3)) + "y") // berries → berry
            keys.insert(String(word.dropLast())) // cookies → cookie
        }
        if word.count > 3, word.hasSuffix("es") {
            keys.insert(String(word.dropLast(2))) // peaches → peach, tomatoes → tomato
        }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
            keys.insert(String(word.dropLast())) // apples → apple
        }
        return keys
    }

    static func same(_ a: String, _ b: String) -> Bool {
        !keys(a).isDisjoint(with: keys(b))
    }
}

/// "Did you mean…?" for a name that looks misspelled. Nothing changes unless you tap the suggestion. On the main
/// thread, where the phone's spelling checker lives.
@MainActor
enum Spelling {
    /// A better spelling of `typed`, or nil when it looks right. A name you've used before wins (a typo of one
    /// of them is corrected to it); otherwise each word goes to `correct`, which returns a fix for a misspelled
    /// word or nil. Words from names you've used before are never corrected, so brand names you buy stay put.
    static func suggestion(for typed: String, known: [String], correct: @MainActor (String) -> String? = systemCorrection) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        if known.contains(where: { GroceryStore.same($0, trimmed) }) { return nil }

        let key = GroceryStore.stem(trimmed)
        if key.count >= 5 {
            let allowed = key.count >= 9 ? 2 : 1
            let near = known
                .map { ($0, GroceryStore.distance(GroceryStore.stem($0), key)) }
                .filter { $0.1 <= allowed }
                .min { $0.1 < $1.1 }
            if let near { return TitleCase.apply(near.0) }
        }

        let knownWords = Set(known.flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) })
        var changed = false
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: false).map { part -> String in
            let word = String(part)
            guard word.count >= 3, word.allSatisfy(\.isLetter), !knownWords.contains(word.lowercased()),
                  let fix = correct(word), fix.caseInsensitiveCompare(word) != .orderedSame else { return word }
            changed = true
            return fix
        }
        return changed ? TitleCase.apply(words.joined(separator: " ")) : nil
    }

    /// The phone's own spelling dictionary: the first guess for a misspelled word, or nil.
    static func systemCorrection(_ word: String) -> String? {
        #if canImport(UIKit)
        let checker = UITextChecker()
        let language = UITextChecker.availableLanguages.first { $0.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            ?? "en_US"
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        guard miss.location != NSNotFound else { return nil }
        return checker.guesses(forWordRange: miss, in: word, language: language)?.first
        #else
        return nil
        #endif
    }
}

/// Allergies and foods to avoid, suggested as you type on the Allergies & Avoid List.
enum AllergenSuggestions {
    /// The major allergens first (shown before you type), then other common ones.
    static let common = [
        "Peanuts", "Tree Nuts", "Milk", "Eggs", "Gluten", "Soy", "Shellfish", "Fish", "Sesame",
        "Wheat", "Dairy", "Lactose", "Almonds", "Cashews", "Walnuts", "Pecans", "Pistachios", "Hazelnuts",
        "Macadamia Nuts", "Brazil Nuts", "Coconut", "Shrimp", "Crab", "Lobster", "Clams", "Oysters", "Mussels",
        "Mustard", "Celery", "Lupin", "Sulfites", "Corn", "Oats", "Barley", "Rye", "Gelatin", "Pork", "Beef",
        "Chicken", "Red Dye", "MSG", "Caffeine", "Alcohol", "Kiwi", "Strawberries", "Tomatoes", "Garlic",
        "Onions", "Peppers", "Avocado", "Bananas", "Chocolate", "Cinnamon", "Nightshades", "Yeast",
    ]

    /// What to offer for what's typed so far: names with a word starting with it first, then names containing
    /// it. Skips anything already on the list, singular or plural. Before you type, the major allergens.
    static func matches(for typed: String, excluding avoided: [String], limit: Int = 8) -> [String] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let available = common.filter { name in !avoided.contains { GroceryStore.same($0, name) } }
        guard !query.isEmpty else { return Array(available.prefix(9)) }
        let startsWord = available.filter { name in
            name.lowercased().split(separator: " ").contains { $0.hasPrefix(query) }
        }
        let contains = available.filter { $0.lowercased().contains(query) && !startsWord.contains($0) }
        return Array((startsWord + contains).prefix(limit))
    }
}

extension GroceryStore {
    /// "Did you mean…?" for a name being typed, checked against names on the list and in history first.
    func spellingSuggestion(for typed: String, correct: @MainActor (String) -> String? = Spelling.systemCorrection) -> String? {
        Spelling.suggestion(for: typed, known: items.map(\.name) + history.map(\.name), correct: correct)
    }
}
