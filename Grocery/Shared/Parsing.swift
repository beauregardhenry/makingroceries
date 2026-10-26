import Foundation

/// Turns "milk, 6 bananas, eggs x2" into items.
enum QuickAdd {
    struct Entry: Equatable {
        var name: String
        var quantity: Int
    }

    static func parse(_ text: String) -> [Entry] {
        text.split(whereSeparator: { ",;\n".contains($0) }).compactMap { part in
            var words = part.split(separator: " ").map(String.init)
            var quantity = 1

            // "6 bananas", "6x bananas"
            if words.count > 1, let n = Int(words[0].trimmingCharacters(in: CharacterSet(charactersIn: "x×X"))), (1...99).contains(n) {
                quantity = n
                words.removeFirst()
            // "bananas x6", "bananas ×6"
            } else if words.count > 1, let last = words.last, last.count > 1, "x×X".contains(last.first!),
                      let n = Int(last.dropFirst()), (1...99).contains(n) {
                quantity = n
                words.removeLast()
            }

            let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Entry(name: name.prefix(1).uppercased() + name.dropFirst(), quantity: quantity)
        }
    }
}

/// Pulls an ingredient list out of pasted text or a recipe web page.
enum RecipeParser {
    struct Recipe {
        var name: String?
        var ingredients: [QuickAdd.Entry]
    }

    private static let units = [
        "cups", "cup", "tablespoons", "tablespoon", "tbsp", "tbs", "teaspoons", "teaspoon", "tsp",
        "ounces", "ounce", "oz", "pounds", "pound", "lbs", "lb", "grams", "gram", "kg", "g",
        "milliliters", "ml", "liters", "liter", "l", "cloves", "clove", "cans", "can", "pinch", "dash",
        "packages", "package", "pkg", "bunches", "bunch", "sticks", "stick", "slices", "slice",
        "jars", "jar", "bags", "bag", "heads", "head", "sprigs", "sprig", "pints", "pint", "quarts", "quart",
    ]

    /// One ingredient per line; headings, blanks and amounts are dropped.
    static func fromText(_ text: String) -> [QuickAdd.Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { clean(line: String($0)) }
    }

    static func clean(line raw: String) -> QuickAdd.Entry? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*–—☐▢□✓✔◦▪ \t"))
        guard !line.isEmpty, !line.hasSuffix(":") else { return nil }

        line = line.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        if let comma = line.firstIndex(of: ",") { line = String(line[..<comma]) }
        line = line.trimmingCharacters(in: .whitespaces)

        var quantity = 1
        let amount = #"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?|[½¼¾⅓⅔⅛])(?:\s*[-–]\s*\d+(?:/\d+)?)?\s*"#
        var hadAmount = false
        var amountText = ""
        if let range = line.range(of: amount, options: .regularExpression) {
            amountText = String(line[range]).trimmingCharacters(in: .whitespaces)
            line.removeSubrange(range)
            hadAmount = true
        }

        var hadUnit = false
        let unitPattern = "^(?:" + units.joined(separator: "|") + #")\b\.?\s*"#
        if hadAmount, let range = line.range(of: unitPattern, options: [.regularExpression, .caseInsensitive]) {
            line.removeSubrange(range)
            hadUnit = true
        }
        if hadAmount, !hadUnit, let n = Int(amountText), (1...20).contains(n) { quantity = n }

        line = line.replacingOccurrences(of: #"^of\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        for tail in [" to taste", " for serving", " as needed", " for garnish", " optional"] where line.lowercased().hasSuffix(tail) {
            line = String(line.dropLast(tail.count))
        }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: " .;-"))
        guard line.count >= 2, line.contains(where: \.isLetter) else { return nil }
        return QuickAdd.Entry(name: line.prefix(1).uppercased() + line.dropFirst(), quantity: quantity)
    }

    /// Reads the schema.org recipe data most recipe sites embed in their pages.
    static func fromHTML(_ html: String) -> Recipe? {
        let pattern = #"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html),
                  let data = String(html[r]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let recipe = findRecipe(in: json) else { continue }
            let lines = (recipe["recipeIngredient"] as? [String]) ?? (recipe["ingredients"] as? [String]) ?? []
            let entries = lines.compactMap { clean(line: decodeEntities($0)) }
            guard !entries.isEmpty else { continue }
            return Recipe(name: (recipe["name"] as? String).map(decodeEntities), ingredients: entries)
        }
        return nil
    }

    private static func findRecipe(in json: Any) -> [String: Any]? {
        if let array = json as? [Any] {
            for element in array { if let found = findRecipe(in: element) { return found } }
        } else if let dict = json as? [String: Any] {
            let type = dict["@type"]
            if (type as? String) == "Recipe" || ((type as? [String])?.contains("Recipe") ?? false) { return dict }
            if let graph = dict["@graph"], let found = findRecipe(in: graph) { return found }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"]
            .reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
