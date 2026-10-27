import Foundation

/// One shopping trip's total, from a receipt or typed in.
struct SpendRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var shopID: UUID?
    var amount: Double
    /// How much went on each aisle (by `Aisle.rawValue`), when a receipt gave the detail.
    var byAisle: [String: Double]?
}

struct SpendBucket: Identifiable, Equatable {
    var id: String
    var label: String
    var amount: Double
}

extension GroceryStore {
    func recordSpend(amount: Double, on date: Date = Date(), shopID: UUID?, byAisle: [String: Double]? = nil) {
        guard amount > 0 else { return }
        spending.append(SpendRecord(date: date, shopID: shopID, amount: amount, byAisle: byAisle))
    }

    func spent(from start: Date, to end: Date) -> Double {
        spending.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
    }

    func monthToDate(now: Date = Date()) -> Double {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return 0 }
        return spent(from: start, to: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now)
    }

    /// Totals for each of the last `weeks` weeks, oldest first, each labelled by the day it starts.
    func weeklyTotals(weeks: Int = 8, now: Date = Date()) -> [SpendBucket] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        return (0..<weeks).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return SpendBucket(id: "\(start.timeIntervalSince1970)", label: start.formatted(.dateTime.month(.abbreviated).day()),
                               amount: spent(from: start, to: end))
        }
    }

    func spendingByShop(from start: Date, to end: Date) -> [SpendBucket] {
        var totals: [String: Double] = [:]
        for r in spending where r.date >= start && r.date < end {
            totals[shopName(for: r.shopID) ?? "Other", default: 0] += r.amount
        }
        return totals.map { SpendBucket(id: $0.key, label: $0.key, amount: $0.value) }.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.label < $1.label }
    }

    func spendingByAisle(from start: Date, to end: Date) -> [SpendBucket] {
        var totals: [String: Double] = [:]
        for r in spending where r.date >= start && r.date < end {
            for (aisle, amount) in r.byAisle ?? [:] { totals[aisle, default: 0] += amount }
        }
        return totals.map { SpendBucket(id: $0.key, label: $0.key, amount: $0.value) }.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.label < $1.label }
    }

    static var monthlyBudget: Double? {
        get { let v = UserDefaults.standard.double(forKey: "monthlyBudget"); return v > 0 ? v : nil }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: "monthlyBudget") }
    }
}
