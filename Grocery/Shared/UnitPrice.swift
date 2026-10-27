import Foundation

/// Package sizes ("16 oz", "500g", "1.5 L", "12 ct") and the price per ounce, fluid ounce or piece.
enum SizeParser {
    private static let units: [String: String] = [
        "oz": "oz", "ounce": "oz", "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
        "g": "g", "gram": "g", "grams": "g", "kg": "kg", "kilogram": "kg", "kilograms": "kg",
        "fl oz": "fl oz", "floz": "fl oz", "fluid ounce": "fl oz", "fluid ounces": "fl oz",
        "ml": "ml", "milliliter": "ml", "milliliters": "ml", "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
        "gal": "gal", "gallon": "gal", "gallons": "gal", "qt": "qt", "quart": "qt", "quarts": "qt", "pt": "pt", "pint": "pt", "pints": "pt",
        "ct": "ct", "count": "ct", "pk": "ct", "pack": "ct", "pc": "ct", "pcs": "ct", "piece": "ct", "pieces": "ct", "each": "ct",
    ]

    /// "16 oz" -> (16, "oz"). "2 x 250 g" multiplies. Nil when there's no size in the text.
    static func parse(_ text: String) -> (amount: Double, unit: String)? {
        let t = text.lowercased().replacingOccurrences(of: ",", with: ".")
        let pattern = #"(?:(\d+)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(fl\.?\s?oz|fluid ounces?|[a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let ar = Range(m.range(at: 2), in: t), let ur = Range(m.range(at: 3), in: t),
              let amount = Double(t[ar]) else { return nil }
        let rawUnit = t[ur].replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        guard let unit = units[rawUnit] else { return nil }
        let multiplier = m.range(at: 1).location != NSNotFound ? Double(t[Range(m.range(at: 1), in: t)!]) ?? 1 : 1
        return (amount * multiplier, unit)
    }

    static func label(_ amount: Double, _ unit: String) -> String {
        (amount == amount.rounded() ? String(Int(amount)) : String(format: "%g", amount)) + " " + unit
    }
}

enum UnitPrice {
    /// The price of one unit of the item's size: per ounce for weight, per fluid ounce for liquids,
    /// per piece for counts. Nil when the size is unknown.
    static func perUnit(price: Double, amount: Double, unit: String) -> (value: Double, label: String)? {
        guard price > 0, amount > 0 else { return nil }
        let (base, label): (Double, String)
        switch unit {
        case "oz": (base, label) = (amount, "oz")
        case "lb": (base, label) = (amount * 16, "oz")
        case "g": (base, label) = (amount / 28.3495, "oz")
        case "kg": (base, label) = (amount * 1000 / 28.3495, "oz")
        case "fl oz": (base, label) = (amount, "fl oz")
        case "ml": (base, label) = (amount / 29.5735, "fl oz")
        case "l": (base, label) = (amount * 1000 / 29.5735, "fl oz")
        case "gal": (base, label) = (amount * 128, "fl oz")
        case "qt": (base, label) = (amount * 32, "fl oz")
        case "pt": (base, label) = (amount * 16, "fl oz")
        case "ct": (base, label) = (amount, "ea")
        default: return nil
        }
        return (price / base, label)
    }

    static func text(price: Double?, amount: Double?, unit: String?) -> String? {
        guard let price, let amount, let unit, let u = perUnit(price: price, amount: amount, unit: unit) else { return nil }
        let money = u.value < 1 ? String(format: "$%.2f", u.value) : String(format: "$%.2f", u.value)
        return "\(money)/\(u.label)"
    }
}

extension GroceryItem {
    var unitPriceText: String? { UnitPrice.text(price: price, amount: sizeAmount, unit: sizeUnit) }
}
