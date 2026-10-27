import Foundation

// MARK: Barcodes

enum ScanOutcome: Equatable {
    case ticked(String)
    case alreadyBought(String)
    case notOnList(String)
    case unknown
}

extension GroceryStore {
    /// The item last scanned with this barcode, if you've scanned it before.
    func pastItem(forBarcode code: String) -> PastItem? {
        history.first { $0.barcode == code }
    }

    func rememberBarcode(_ code: String, for name: String) {
        guard let i = history.firstIndex(where: { Self.same($0.name, name) }) else { return }
        history[i].barcode = code
    }

    /// Ticks off the list item a barcode belongs to. The first time, the product's name from
    /// `lookup` is matched to your list and the barcode is remembered, so it works instantly after that.
    @MainActor
    func checkOff(barcode code: String, preferring shopID: UUID?, lookup: (String) async -> String?) async -> ScanOutcome {
        var name = pastItem(forBarcode: code)?.name
        var learned = name != nil
        if name == nil {
            guard let found = await lookup(code) else { return .unknown }
            name = found
        }
        guard let productName = name else { return .unknown }

        let candidates = items.filter { item in
            learned ? Self.same(item.name, productName)
                    : ReceiptMatcher.score(productName, item.name) >= 0.99
        }
        let pending = candidates.filter { !$0.isChecked }
        if let item = pending.first(where: { $0.shopID == shopID }) ?? pending.first {
            if !learned { rememberBarcode(code, for: item.name); learned = true }
            toggle(item)
            return .ticked(item.name)
        }
        if let done = candidates.first {
            return .alreadyBought(done.name)
        }
        return .notOnList(productName)
    }
}
