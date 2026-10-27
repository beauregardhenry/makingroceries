import Foundation

/// One item checked off at a store, remembered so the app can learn the order you walk the aisles in.
struct RouteEvent: Codable, Equatable, Hashable {
    var aisle: Aisle
    var date: Date
}

enum RouteLearning {
    /// A gap this long between two check-offs starts a new shopping trip.
    static let tripGap: TimeInterval = 2 * 3600
    static let minimumTrips = 3
    static let maximumEvents = 300

    /// Each trip as the aisles in the order you first checked something off in them.
    static func trips(from events: [RouteEvent]) -> [[Aisle]] {
        var trips: [[Aisle]] = []
        var current: [Aisle] = []
        var last: Date?
        for event in events.sorted(by: { $0.date < $1.date }) {
            if let last, event.date.timeIntervalSince(last) > tripGap {
                trips.append(current)
                current = []
            }
            if !current.contains(event.aisle) { current.append(event.aisle) }
            last = event.date
        }
        if !current.isEmpty { trips.append(current) }
        return trips.filter { $0.count >= 2 }
    }

    /// The learned order, or nil while there isn't enough to go on or nothing would change.
    /// Aisles you haven't shopped keep their current places; the ones you have are put in the
    /// order they most often came, using how many trips had one before the other.
    static func order(current: [Aisle], events: [RouteEvent]) -> [Aisle]? {
        let trips = trips(from: events)
        guard trips.count >= minimumTrips else { return nil }

        var score: [Aisle: Int] = [:]
        for trip in trips {
            for (i, a) in trip.enumerated() {
                for b in trip[(i + 1)...] {
                    score[a, default: 0] += 1
                    score[b, default: 0] -= 1
                }
            }
        }
        let seen = Set(trips.flatMap { $0 })
        let slots = current.indices.filter { seen.contains(current[$0]) }
        let ranked = slots.map { current[$0] }.sorted { a, b in
            let (sa, sb) = (score[a] ?? 0, score[b] ?? 0)
            if sa != sb { return sa > sb }
            return (current.firstIndex(of: a) ?? 0) < (current.firstIndex(of: b) ?? 0)
        }
        var result = current
        for (slot, aisle) in zip(slots, ranked) { result[slot] = aisle }
        return result == current ? nil : result
    }
}
