import Foundation

/// Something you're saving up for: a computer, a van repair, a trip.
struct Goal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// What it costs.
    var cost: Double
    /// Money already set aside for it.
    var saved: Double = 0
    var note: String?
    /// The rainy-day fund: money kept back to cover surprises without upsetting the other goals. Nil means no.
    var isReserve: Bool?
    var added = Date()
    /// Set when it's been bought (or an unexpected expense was paid), so it moves to the done pile.
    var completed: Date?

    var reserve: Bool { isReserve == true }
    var isDone: Bool { completed != nil }
    var remaining: Double { max(cost - saved, 0) }
    /// 0 to 1.
    var progress: Double { cost > 0 ? min(max(saved / cost, 0), 1) : 1 }
}

/// When each goal will be funded if you put the same amount aside every month, funding them in priority order.
struct GoalForecast: Equatable {
    var goalID: UUID
    var remaining: Double
    /// Nil when there's no monthly amount to project from.
    var date: Date?
    var isFunded: Bool { remaining <= 0 }
}

enum GoalPlanner {
    static let daysPerMonth = 30.4375

    /// Each month's money goes to the first goal that isn't funded yet, then the next. A goal's date is
    /// when everything ahead of it, plus its own remainder, has been covered.
    static func forecast(_ goals: [Goal], monthly: Double, from now: Date = Date()) -> [GoalForecast] {
        var running = 0.0
        return goals.filter { !$0.isDone }.map { goal in
            let remaining = goal.remaining
            running += remaining
            let date: Date?
            if remaining <= 0 {
                date = now
            } else if monthly > 0 {
                date = Calendar.current.date(byAdding: .day, value: Int((running / monthly * daysPerMonth).rounded(.up)), to: now)
            } else {
                date = nil
            }
            return GoalForecast(goalID: goal.id, remaining: remaining, date: date)
        }
    }

    /// How many days an extra cost pushes every goal behind it back.
    static func delayDays(adding cost: Double, monthly: Double) -> Int? {
        guard monthly > 0, cost > 0 else { return nil }
        return Int((cost / monthly * daysPerMonth).rounded(.up))
    }

    /// "less than a week", "about 3 weeks", "about 2 months".
    static func delayText(days: Int) -> String {
        switch days {
        case ..<7: return "less than a week"
        case 7..<60:
            let weeks = Int((Double(days) / 7).rounded())
            return "about \(weeks) \(weeks == 1 ? "week" : "weeks")"
        default:
            let months = Int((Double(days) / daysPerMonth).rounded())
            return "about \(months) months"
        }
    }
}

/// Where a new goal or surprise expense goes in the priority order.
enum GoalPriority: String, CaseIterable, Identifiable {
    case urgent = "Urgent, do first"
    case normal = "When I can"

    var id: String { rawValue }
}

extension GroceryStore {
    var activeGoals: [Goal] { goals.filter { !$0.isDone } }
    var doneGoals: [Goal] { goals.filter(\.isDone) }
    var reserveGoal: Goal? { activeGoals.first(where: \.reserve) }

    /// Adds a goal. Urgent ones go to the top of the order; others to the bottom of what's still to do.
    @discardableResult
    func addGoal(name: String, cost: Double, saved: Double = 0, priority: GoalPriority = .normal,
                 isReserve: Bool = false, note: String? = nil) -> Goal? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, cost > 0 else { return nil }
        // Only one rainy-day fund.
        let reserve = isReserve && reserveGoal == nil
        var goal = Goal(name: trimmed, cost: cost, saved: min(max(saved, 0), cost), note: note)
        goal.isReserve = reserve ? true : nil
        var active = activeGoals
        if priority == .urgent { active.insert(goal, at: 0) } else { active.append(goal) }
        goals = active + doneGoals
        return goal
    }

    /// Reorders the goals still to do; done ones stay at the end.
    func moveGoals(from offsets: IndexSet, to destination: Int) {
        var active = activeGoals
        active.move(fromOffsets: offsets, toOffset: destination)
        goals = active + doneGoals
    }

    func makeTopPriority(_ id: UUID) {
        guard let goal = activeGoals.first(where: { $0.id == id }) else { return }
        goals = [goal] + activeGoals.filter { $0.id != id } + doneGoals
    }

    func setAside(_ amount: Double, for id: UUID) {
        guard let i = goals.firstIndex(where: { $0.id == id }), !goals[i].isDone else { return }
        goals[i].saved = min(max(goals[i].saved + amount, 0), goals[i].cost)
    }

    /// Marks a goal bought. It moves to the done pile, keeping the order of the rest.
    func markBought(_ id: UUID, on date: Date = Date()) {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { return }
        var goal = goals.remove(at: i)
        goal.completed = date
        goals = activeGoals + doneGoals + [goal]
    }

    /// Puts a bought goal back at the end of the list of things to save for.
    func reopen(_ id: UUID) {
        guard let i = goals.firstIndex(where: { $0.id == id }) else { return }
        var goal = goals.remove(at: i)
        goal.completed = nil
        goals = activeGoals + [goal] + doneGoals
    }

    func deleteGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
    }

    /// An unexpected expense, like the van needing a repair. If the rainy-day fund has enough it's paid from
    /// there (and logged as done) and nothing else moves; otherwise it becomes a goal in the order you choose.
    /// Returns true when the rainy-day fund paid for it.
    @discardableResult
    func addUnexpected(name: String, cost: Double, priority: GoalPriority, useReserve: Bool, on date: Date = Date()) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, cost > 0 else { return false }
        if useReserve, let reserve = reserveGoal, reserve.saved >= cost {
            setAside(-cost, for: reserve.id)
            var paid = Goal(name: trimmed, cost: cost, saved: cost)
            paid.completed = date
            goals.append(paid)
            return true
        }
        addGoal(name: trimmed, cost: cost, priority: priority)
        return false
    }

    /// Adds up what's still needed and what's already set aside across the goals still to do.
    var goalTotals: (cost: Double, saved: Double, remaining: Double) {
        let active = activeGoals
        return (active.reduce(0) { $0 + $1.cost }, active.reduce(0) { $0 + $1.saved }, active.reduce(0) { $0 + $1.remaining })
    }
}

/// The running total shown under the list: everything priced on screen, what's already in the cart, and
/// across every everyday list when a single store is showing.
struct RunningTotal: Equatable {
    var all = 0.0
    var inCart = 0.0
    var pricedCount = 0
    var count = 0
    /// Across every list except Travel, only when it differs from the list on screen.
    var everywhere: Double?

    init(visible: [GroceryItem], everyday: [GroceryItem]) {
        let shown = Totals(visible)
        all = shown.sum
        pricedCount = shown.priced
        count = shown.count
        inCart = Totals(visible.filter(\.isChecked)).sum
        let everything = Totals(everyday).sum
        if abs(everything - all) > 0.004 { everywhere = everything }
    }
}
