import Foundation

enum Price {
    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    /// Accepts "3", "3.49", "$3,49"; nil for anything that isn't a non-negative number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    /// Text for an editing field: no currency symbol, no trailing zeros noise.
    static func editText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}

extension GroceryItem {
    /// Price of the whole quantity.
    var lineTotal: Double? { price.map { $0 * Double(quantity) } }
}

struct Totals {
    var sum = 0.0
    var priced = 0
    var count = 0

    init(_ items: [GroceryItem]) {
        for item in items {
            count += 1
            if let line = item.lineTotal {
                sum += line
                priced += 1
            }
        }
    }
}
