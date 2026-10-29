import Foundation

/// An item's recorded prices, read for patterns: what you usually pay, whether the latest is a real
/// deal, and which store is reliably cheapest.
struct PriceTrend: Equatable {
    struct StoreSummary: Equatable, Identifiable {
        /// Nil for prices with no store.
        var shopID: UUID?
        var name: String
        var average: Double
        var latest: Double
        var count: Int
        var id: String { shopID?.uuidString ?? "none" }
    }

    var name: String
    /// Oldest first.
    var points: [PricePoint]
    /// The middle of what you've paid, which a single sale or price jump doesn't move much.
    var usual: Double
    var latest: PricePoint
    var stores: [StoreSummary]

    /// How far the latest price is below the usual one, as a fraction (0.2 is 20% off), or nil if it isn't.
    var discount: Double? {
        guard points.count >= 3, usual > 0 else { return nil }
        let off = (usual - latest.price) / usual
        return off >= PriceTrend.dealThreshold ? off : nil
    }

    /// The store with the lowest average, once at least two stores have prices.
    var cheapestStore: StoreSummary? {
        let named = stores.filter { $0.shopID != nil }
        guard named.count >= 2 else { return nil }
        return named.min { $0.average < $1.average }
    }

    /// How much less the cheapest store averages than the dearest, per item.
    var spread: Double {
        let averages = stores.filter { $0.shopID != nil }.map(\.average)
        guard let low = averages.min(), let high = averages.max() else { return 0 }
        return high - low
    }

    static let dealThreshold = 0.10

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

extension GroceryStore {
    /// The price pattern for one item, or nil until it has at least two prices.
    func priceTrend(for name: String) -> PriceTrend? {
        guard let past = pastItem(named: name),
              let points = past.priceHistory?.sorted(by: { $0.date < $1.date }),
              points.count >= 2, let latest = points.last else { return nil }
        let byStore = Dictionary(grouping: points) { point -> UUID? in
            point.shopID.flatMap { shop(for: $0) != nil ? $0 : nil }
        }
        let stores = byStore.map { id, prices in
            PriceTrend.StoreSummary(shopID: id, name: shopName(for: id) ?? "No store",
                                    average: prices.map(\.price).reduce(0, +) / Double(prices.count),
                                    latest: prices.last?.price ?? 0, count: prices.count)
        }
        .sorted { $0.average < $1.average }
        return PriceTrend(name: past.name, points: points, usual: PriceTrend.median(points.map(\.price)),
                          latest: latest, stores: stores)
    }

    /// Items whose latest price is well under what you usually pay, biggest discount first.
    func priceDeals() -> [PriceTrend] {
        history.compactMap { priceTrend(for: $0.name) }
            .filter { $0.discount != nil }
            .sorted { ($0.discount ?? 0) > ($1.discount ?? 0) }
    }

    /// For the things you buy most, where each is cheapest on average, biggest gap between stores first.
    func cheapestStores(limit: Int = 20) -> [PriceTrend] {
        history.sorted { $0.count > $1.count }
            .compactMap { priceTrend(for: $0.name) }
            .filter { $0.cheapestStore != nil && $0.spread >= 0.01 }
            .sorted { $0.spread > $1.spread }
            .prefix(limit).map { $0 }
    }
}
