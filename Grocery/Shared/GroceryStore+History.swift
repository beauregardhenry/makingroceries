import Foundation

extension GroceryStore {
    // MARK: History, autocomplete and buy again

    func pastItem(named name: String) -> PastItem? {
        history.first { Self.same($0.name, name) }
    }

    func resolveAisle(for name: String) -> Aisle {
        pastItem(named: name)?.aisle ?? Aisle.guess(fromCategories: [name]) ?? .other
    }

    func remember(name: String, aisle: Aisle, shopID: UUID?, price: Double?, countsAsUse: Bool = true) {
        let point = price.map { PricePoint(shopID: shopID, price: $0, date: Date()) }
        if let i = history.firstIndex(where: { Self.same($0.name, name) }) {
            history[i].aisle = aisle
            history[i].shopID = shopID
            if let price { history[i].price = price }
            if let point { Self.append(point, to: &history[i]) }
            if countsAsUse {
                history[i].count += 1
                history[i].lastUsed = Date()
            }
        } else {
            var past = PastItem(name: name, aisle: aisle, shopID: shopID, price: price)
            if let point { Self.append(point, to: &past) }
            history.append(past)
        }
    }

    /// Keeps a short price trail, skipping a repeat of the latest price at the same store.
    static func append(_ point: PricePoint, to past: inout PastItem) {
        var trail = past.priceHistory ?? []
        if let last = trail.last(where: { $0.shopID == point.shopID }), abs(last.price - point.price) < 0.005 { return }
        trail.append(point)
        past.priceHistory = Array(trail.suffix(30))
    }

    func recordPurchase(of name: String) {
        guard let i = history.firstIndex(where: { Self.same($0.name, name) }) else { return }
        var dates = history[i].purchases ?? []
        if let last = dates.last, Calendar.current.isDateInToday(last) { return }
        dates.append(Date())
        history[i].purchases = Array(dates.suffix(12))
    }

    /// Past items starting with `prefix`, most used first, skipping what's already on the list.
    func suggestions(for prefix: String, limit: Int = 6) -> [PastItem] {
        let prefix = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !prefix.isEmpty else { return [] }
        return history
            .filter { $0.name.lowercased().hasPrefix(prefix) && $0.name.lowercased() != prefix && !isOnList($0.name) }
            .sorted { ($0.count, $0.lastUsed) > ($1.count, $1.lastUsed) }
            .prefix(limit).map { $0 }
    }

    /// Past items not on the list now, most recent first.
    func buyAgain(limit: Int = 25) -> [PastItem] {
        history.filter { !isOnList($0.name) }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit).map { $0 }
    }

    /// Items you buy at a steady pace that are about due, judged from when you checked them off.
    func dueItems(limit: Int = 4, now: Date = Date()) -> [PastItem] {
        history.compactMap { past -> (PastItem, Double)? in
            guard let dates = past.purchases?.sorted(), dates.count >= 3, !isOnList(past.name) else { return nil }
            let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
            let average = gaps.reduce(0, +) / Double(gaps.count)
            guard average >= 86_400 else { return nil }
            let ratio = now.timeIntervalSince(dates.last!) / average
            return ratio >= 0.85 ? (past, ratio) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit).map(\.0)
    }

    /// A short hint when the same item cost less at another store you've priced it in.
    func priceHint(for item: GroceryItem) -> String? {
        guard let trail = pastItem(named: item.name)?.priceHistory else { return nil }
        var latest: [UUID?: PricePoint] = [:]
        for point in trail.sorted(by: { $0.date < $1.date }) { latest[point.shopID] = point }
        let named = latest.values.filter { shop(for: $0.shopID) != nil }
        guard named.count >= 2, let best = named.min(by: { $0.price < $1.price }) else { return nil }
        if let price = item.price, best.price >= price - 0.005 { return nil }
        if best.shopID == item.shopID { return nil }
        let cost = best.price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        return "Cheaper at \(shopName(for: best.shopID) ?? "another store"): \(cost)"
    }

    // MARK: Spelling

    /// The known spelling of a name (from the list or history) when the typed one is the same
    /// word in another case, singular or plural, or a one- or two-letter typo; otherwise as typed.
    func canonicalName(for typed: String) -> String {
        let known = items.map(\.name) + history.map(\.name)
        if let exact = known.first(where: { Self.same($0, typed) }) { return exact }
        let key = Self.stem(typed)
        if let match = known.first(where: { Self.stem($0) == key }) { return match }
        guard key.count >= 5 else { return typed }
        let allowed = key.count >= 9 ? 2 : 1
        let near = known
            .map { ($0, Self.distance(Self.stem($0), key)) }
            .filter { $0.1 <= allowed }
            .min { $0.1 < $1.1 }
        return near?.0 ?? typed
    }

    static func stem(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.count > 4, s.hasSuffix("ies") { s = String(s.dropLast(3)) + "y" }
        else if s.count > 4, s.hasSuffix("oes") { s = String(s.dropLast(2)) }
        else if s.count > 3, s.hasSuffix("s"), !s.hasSuffix("ss") { s = String(s.dropLast()) }
        return s
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
