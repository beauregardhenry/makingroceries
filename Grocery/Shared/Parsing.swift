import Foundation

/// Turns "milk, 6 bananas, eggs x2" into items. With `spoken`, also understands dictation:
/// "two limes and a dozen eggs".
enum QuickAdd {
    struct Entry: Equatable {
        var name: String
        var quantity: Int
    }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "dozen": 12,
    ]

    /// Dictation puts "and" between items and often a leading "add"; written lists use commas.
    static func normalizeSpoken(_ text: String) -> String {
        var t = text.lowercased()
        t = t.replacingOccurrences(of: #"^\s*(please\s+)?(add|put|get|buy|pick up)\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+(to|on|onto)\s+(my|the)\s+(grocery\s+)?list\b.*$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+and\s+"#, with: ", ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[.!?]"#, with: "", options: .regularExpression)
        return t
    }

    static func parse(_ text: String, spoken: Bool = false) -> [Entry] {
        let source = spoken ? normalizeSpoken(text) : text
        return source.split(whereSeparator: { ",;\n".contains($0) }).compactMap { part in
            var words = part.split(separator: " ").map(String.init)
            var quantity = 1

            // "a dozen eggs", "an apple" (spoken)
            if spoken, words.count > 2, ["a", "an"].contains(words[0].lowercased()), words[1].lowercased() == "dozen" {
                quantity = 12
                words.removeFirst(2)
            } else if spoken, words.count > 1, ["a", "an"].contains(words[0].lowercased()) {
                words.removeFirst()
            // "two limes", "twelve eggs" (spoken)
            } else if spoken, words.count > 1, let n = numberWords[words[0].lowercased()], words[0].lowercased() != "dozen" {
                quantity = n
                words.removeFirst()
            // "6 bananas", "6x bananas"
            } else if words.count > 1, let n = Int(words[0].trimmingCharacters(in: CharacterSet(charactersIn: "x×X"))), (1...99).contains(n) {
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

/// One ingredient line from a recipe.
struct RecipeLine: Equatable {
    var name: String
    /// How many to buy when there is no unit: "3 eggs" is 3. Lines with a unit use 1.
    var quantity: Int = 1
    /// Amount and unit for measured ingredients: "2 cups flour" is 2 and "cup".
    var amount: Double?
    var unit: String?
}

/// Amounts for recipes: reading "1 1/2", showing "1½", and scaling a batch.
enum Amount {
    private static let glyphs: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
    private static let fractions: [(Double, String)] = [(0, ""), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "")]
    private static let abbreviations: Set<String> = ["tbsp", "tsp", "oz", "lb", "g", "kg", "ml", "l"]
    private static let singular = [
        "cups": "cup", "tablespoons": "tablespoon", "teaspoons": "teaspoon", "ounces": "ounce", "pounds": "pound",
        "lbs": "lb", "grams": "gram", "milliliters": "milliliter", "liters": "liter", "cloves": "clove",
        "cans": "can", "packages": "package", "pkg": "package", "bunches": "bunch", "sticks": "stick",
        "slices": "slice", "jars": "jar", "bags": "bag", "heads": "head", "sprigs": "sprig", "pints": "pint",
        "quarts": "quart", "tbs": "tbsp",
    ]

    /// "1 1/2" is 1.5, "½" is 0.5, "1½" is 1.5, "2-3" is 2 (the lower end).
    static func parse(_ text: String) -> Double? {
        let first = text.split(whereSeparator: { "-–—".contains($0) }).first.map(String.init) ?? text
        var total = 0.0
        var found = false
        for token in first.split(separator: " ") {
            var token = Substring(token)
            if let last = token.last, let value = glyphs[last] {
                total += value
                found = true
                token = token.dropLast()
                if token.isEmpty { continue }
            }
            if token.contains("/") {
                let parts = token.split(separator: "/")
                guard parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 else { return nil }
                total += n / d
                found = true
            } else if let value = Double(token) {
                total += value
                found = true
            } else {
                return nil
            }
        }
        return found ? total : nil
    }

    /// 1.5 as "1½", 2 as "2", 0.333 as "⅓"; other values with up to two decimals.
    static func format(_ value: Double) -> String {
        var whole = value.rounded(.down)
        let rest = value - whole
        guard let match = fractions.min(by: { abs($0.0 - rest) < abs($1.0 - rest) }), abs(match.0 - rest) < 0.04 else {
            return (round(value * 100) / 100).formatted(.number.precision(.fractionLength(0...2)))
        }
        if match.0 == 1 { whole += 1 }
        if whole == 0 && match.1.isEmpty { return "0" }
        return (whole > 0 ? String(Int(whole)) : "") + match.1
    }

    static func canonicalUnit(_ raw: String) -> String {
        let unit = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))
        return singular[unit] ?? unit
    }

    /// "cup" for one or less, "cups" for more; abbreviations never change.
    static func unitLabel(_ unit: String, for amount: Double) -> String {
        guard amount > 1.0001, !abbreviations.contains(unit) else { return unit }
        if unit.hasSuffix("ch") || unit.hasSuffix("sh") { return unit + "es" }
        return unit + "s"
    }

    /// "2 cups", for an amount and unit.
    static func text(_ amount: Double, unit: String) -> String {
        "\(format(amount)) \(unitLabel(unit, for: amount))"
    }
}

/// Pulls an ingredient list out of pasted text, a photo of a recipe, or a recipe web page.
enum RecipeParser {
    struct Recipe {
        var name: String?
        /// The ingredient lines as written, amounts included.
        var lines: [String]
    }

    private static let units = [
        "cups", "cup", "tablespoons", "tablespoon", "tbsp", "tbs", "teaspoons", "teaspoon", "tsp",
        "ounces", "ounce", "oz", "pounds", "pound", "lbs", "lb", "grams", "gram", "kg", "g",
        "milliliters", "ml", "liters", "liter", "l", "cloves", "clove", "cans", "can", "pinch", "dash",
        "packages", "package", "pkg", "bunches", "bunch", "sticks", "stick", "slices", "slice",
        "jars", "jar", "bags", "bag", "heads", "head", "sprigs", "sprig", "pints", "pint", "quarts", "quart",
    ]

    /// Section titles and other lines that are never ingredients.
    private static let headings: Set<String> = [
        "ingredients", "ingredient", "directions", "instructions", "method", "preparation", "steps", "notes",
        "for the sauce", "for the filling", "for serving", "to serve", "garnish", "topping", "nutrition",
    ]
    private static let metadataPrefixes = ["serves", "servings", "yield", "makes", "prep", "cook", "total time", "calories", "course", "cuisine"]

    /// One ingredient per line; headings, blanks and instructions are dropped.
    static func fromText(_ text: String) -> [RecipeLine] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return ingredientSection(of: lines).compactMap { clean(line: $0) }
    }

    private static let stopHeadings: Set<String> = ["directions", "instructions", "method", "preparation", "steps", "procedure"]

    private static func headingKey(_ line: String) -> String {
        line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":. \t-–—*#"))
    }

    /// A whole recipe page has a title, serving info and steps around the ingredients. When there is
    /// an "Ingredients" heading, keep what is between it and the steps; otherwise keep everything.
    static func ingredientSection(of lines: [String]) -> [String] {
        guard let start = lines.firstIndex(where: { ["ingredients", "ingredient"].contains(headingKey($0)) }) else { return lines }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { stopHeadings.contains(headingKey($0)) }) ?? rest.endIndex
        return Array(rest[..<end])
    }

    /// Text read from a photo breaks long lines in the middle. A line that starts in lower
    /// case continues the one before it.
    static func joinWrappedLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let last = result.last, let first = line.first, first.isLowercase,
               !last.hasSuffix(":"), !headings.contains(last.lowercased()) {
                result[result.count - 1] = last + " " + line
            } else {
                result.append(line)
            }
        }
        return result
    }

    static func clean(line raw: String) -> RecipeLine? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*–—☐▢□✓✔◦▪·o \t"))
        guard !line.isEmpty, !line.hasSuffix(":") else { return nil }

        let lowered = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":. "))
        if headings.contains(lowered) { return nil }
        if metadataPrefixes.contains(where: { lowered.hasPrefix($0 + " ") || lowered.hasPrefix($0 + ":") }) { return nil }
        // Numbered steps ("1. Preheat the oven") and sentences are instructions, not ingredients.
        if line.range(of: #"^\d+[.)]\s+\p{L}"#, options: .regularExpression) != nil { return nil }
        if line.hasSuffix("."), line.split(separator: " ").count > 6 { return nil }

        line = line.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        if let comma = line.firstIndex(of: ",") { line = String(line[..<comma]) }
        line = line.trimmingCharacters(in: .whitespaces)

        let amountPattern = #"^(\d+\s+\d+/\d+|\d+\s*[½¼¾⅓⅔⅛]|\d+/\d+|\d+(?:\.\d+)?|[½¼¾⅓⅔⅛])(?:\s*[-–]\s*\d+(?:/\d+)?)?\s*"#
        var amount: Double?
        if let range = line.range(of: amountPattern, options: .regularExpression) {
            amount = Amount.parse(String(line[range]).trimmingCharacters(in: .whitespaces))
            line.removeSubrange(range)
        }

        var unit: String?
        let unitPattern = "^(?:" + units.joined(separator: "|") + #")\b\.?\s*"#
        if amount != nil, let range = line.range(of: unitPattern, options: [.regularExpression, .caseInsensitive]) {
            unit = Amount.canonicalUnit(String(line[range]))
            line.removeSubrange(range)
        }

        line = line.replacingOccurrences(of: #"^of\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        for tail in [" to taste", " for serving", " as needed", " for garnish", " optional"] where line.lowercased().hasSuffix(tail) {
            line = String(line.dropLast(tail.count))
        }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: " .;-"))
        guard line.count >= 2, line.contains(where: \.isLetter) else { return nil }
        let name = line.prefix(1).uppercased() + line.dropFirst()

        if let unit, let amount { return RecipeLine(name: name, quantity: 1, amount: amount, unit: unit) }
        let count = amount.map { min(99, max(1, Int($0.rounded(.up)))) } ?? 1
        return RecipeLine(name: name, quantity: count)
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
            let raw = (recipe["recipeIngredient"] as? [String]) ?? (recipe["ingredients"] as? [String]) ?? []
            let lines = raw.map(decodeEntities).filter { clean(line: $0) != nil }
            guard !lines.isEmpty else { continue }
            return Recipe(name: (recipe["name"] as? String).map(decodeEntities), lines: lines)
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
