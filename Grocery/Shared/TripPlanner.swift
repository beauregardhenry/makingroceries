import Foundation

/// A suggestion to buy an item at a different store you're already going to.
struct TripMove: Identifiable, Equatable {
    var id: UUID { item.id }
    var item: GroceryItem
    var to: UUID
    var toPrice: Double
    /// What it costs now, if known.
    var fromPrice: Double?
    var savings: Double
}

extension GroceryStore {
    /// The latest price you've recorded for an item at each store that still exists.
    func latestPrices(for name: String) -> [UUID: Double] {
        guard let trail = pastItem(named: name)?.priceHistory else { return [:] }
        var latest: [UUID: PricePoint] = [:]
        for point in trail.sorted(by: { $0.date < $1.date }) {
            if let id = point.shopID, shop(for: id) != nil { latest[id] = point }
        }
        return latest.mapValues(\.price)
    }

    /// Items that cost less at another store on today's trip. A store counts as "on the trip" when it
    /// has something still to buy, so following the plan never adds a stop.
    func tripPlan(minimumSaving: Double = 0.10) -> [TripMove] {
        let pending = items.filter { !$0.isChecked }
        let stops = Set(pending.compactMap(\.shopID))
        guard stops.count >= 1 else { return [] }

        var moves: [TripMove] = []
        for item in pending {
            let prices = latestPrices(for: item.name).filter { stops.contains($0.key) }
            guard let best = prices.min(by: { $0.value < $1.value }) else { continue }
            let quantity = Double(item.quantity)

            if let current = item.shopID {
                guard best.key != current else { continue }
                let paying = item.price ?? latestPrices(for: item.name)[current]
                guard let paying, (paying - best.value) * quantity >= minimumSaving else { continue }
                moves.append(TripMove(item: item, to: best.key, toPrice: best.value, fromPrice: paying,
                                      savings: (paying - best.value) * quantity))
            } else {
                // Not tied to a store yet: send it to the cheapest stop, measured against the dearest.
                guard prices.count >= 2, let worst = prices.values.max(),
                      (worst - best.value) * quantity >= minimumSaving else { continue }
                moves.append(TripMove(item: item, to: best.key, toPrice: best.value, fromPrice: worst,
                                      savings: (worst - best.value) * quantity))
            }
        }
        return moves.sorted { $0.savings > $1.savings }
    }

    /// Moves the chosen items to their cheaper stores and updates their prices to match.
    func applyTripMoves(_ moves: [TripMove]) {
        for move in moves {
            guard let i = items.firstIndex(where: { $0.id == move.item.id }) else { continue }
            items[i].shopID = move.to
            items[i].price = move.toPrice
        }
    }
}
