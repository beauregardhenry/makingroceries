import Foundation

/// One purchased item read off a receipt.
struct ReceiptEntry: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quantity = 1
    /// What one cost.
    var unitPrice: Double
    var total: Double
}

enum ReceiptParser {
    /// Words that mark a line as something other than a purchased item.
    private static let skipWords: [String] = [
        "subtotal", "sub total", "total", "tax", "balance", "change", "cash", "credit", "debit", "visa",
        "mastercard", "amex", "discover", "tender", "payment", "savings", "you saved", "discount", "coupon",
        "points", "rewards", "thank", "phone", "tel:", "www.", ".com", "approved", "auth", "receipt",
        "cashier", "transaction", "items sold", "card", "survey", "member", "store #", "register", "terminal",
        "refund", "void", "amount due", "amt", "tip",
    ]

    private static let pricePattern = try! NSRegularExpression(pattern: #"(-?\$?\d{1,4}[.,]\d{2})\s*[A-Za-z]{0,2}\s*$"#)
    private static let quantityPattern = try! NSRegularExpression(pattern: #"(\d{1,2})\s*(?:@|x|X|for)\s*\$?(\d{1,4}[.,]\d{2})"#)

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "."))
    }

    /// Turns rows of receipt text into purchased items. A "2 @ 0.29" line after an item gives its
    /// quantity; discounts, tax, totals, payment and store details are skipped.
    static func parse(rows: [String]) -> [ReceiptEntry] {
        var entries: [ReceiptEntry] = []
        for raw in rows {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            let range = NSRange(line.startIndex..., in: line)

            // "6 @ 0.29" on its own line belongs to the item above it.
            if let q = quantityPattern.firstMatch(in: line, range: range),
               let qr = Range(q.range(at: 1), in: line), let ur = Range(q.range(at: 2), in: line),
               let qty = Int(line[qr]), let unit = number(String(line[ur])) {
                let rest = (line as NSString).replacingCharacters(in: q.range, with: "").trimmingCharacters(in: .whitespaces)
                let stripped = rest.trimmingCharacters(in: CharacterSet(charactersIn: "$.,0123456789 -"))
                if stripped.count < 2, let last = entries.indices.last, entries[last].quantity == 1 {
                    entries[last].quantity = qty
                    entries[last].unitPrice = unit
                    continue
                }
            }

            if skipWords.contains(where: { lower.contains($0) }) { continue }
            guard let m = pricePattern.firstMatch(in: line, range: range),
                  let pr = Range(m.range(at: 1), in: line),
                  let total = number(String(line[pr])), total > 0 else { continue }

            var name = String(line[..<pr.lowerBound])
            name = name.replacingOccurrences(of: #"^\s*\d{4,}\s+"#, with: "", options: .regularExpression)   // item code
            name = name.replacingOccurrences(of: #"\d+(\.\d+)?\s*(lb|lbs|kg|oz)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            name = name.replacingOccurrences(of: #"\s+[@x]\s*\d.*$"#, with: "", options: .regularExpression)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .-*#$"))
            guard name.count >= 2, name.contains(where: \.isLetter) else { continue }

            entries.append(ReceiptEntry(name: titleCase(name), quantity: 1, unitPrice: total, total: total))
        }
        for i in entries.indices where entries[i].quantity > 1 {
            entries[i].total = (entries[i].unitPrice * Double(entries[i].quantity) * 100).rounded() / 100
        }
        return entries
    }

    static func titleCase(_ text: String) -> String {
        text.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

enum ReceiptMatcher {
    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map { GroceryStore.stem(String($0)) }.filter { $0.count >= 2 }
    }

    /// Receipts abbreviate ("CHKN" for chicken): the short word's letters appear in order in the long one.
    private static func abbreviates(_ short: String, _ long: String) -> Bool {
        guard short.count >= 3, short.first == long.first, short.count < long.count else { return false }
        var rest = Substring(long)
        for ch in short {
            guard let at = rest.firstIndex(of: ch) else { return false }
            rest = rest[rest.index(after: at)...]
        }
        return true
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a == b || abbreviates(a, b) || abbreviates(b, a)
    }

    /// How alike a receipt line and a list item are, 0 to 1.
    static func score(_ receipt: String, _ item: String) -> Double {
        let r = tokens(receipt), i = tokens(item)
        guard !r.isEmpty, !i.isEmpty else { return 0 }
        let shared = i.filter { token in r.contains { same($0, token) } }.count
        return Double(shared) / Double(i.count)
    }

    /// The list item a receipt line is most likely for, if any is a good enough match.
    static func bestMatch(for entry: ReceiptEntry, in items: [GroceryItem]) -> GroceryItem? {
        items
            .map { ($0, score(entry.name, $0.name)) }
            .filter { $0.1 >= 0.99 }
            .max { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.isChecked && !b.0.isChecked   // prefer an item you ticked off
            }?.0
    }
}
